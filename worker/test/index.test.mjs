// Smoke test for the get.resq.software Worker. Runs against the real
// raw.githubusercontent.com upstream, so a pass here means the pinned digests
// are genuinely correct, not just internally consistent.

const store = new Map();
globalThis.caches = {
  default: {
    async match(req) {
      const hit = store.get(req.url);
      return hit ? new Response(hit) : undefined;
    },
    async put(req, res) {
      store.set(req.url, new Uint8Array(await res.arrayBuffer()));
    },
  },
};

const worker = (
  await import("../src/index.js")
).default;

const ctx = { waitUntil: (p) => p.catch(() => {}) };
const call = (path, init = {}, env = {}) =>
  worker.fetch(new Request(`https://get.resq.software${path}`, init), env, ctx);

let pass = 0;
let fail = 0;
function check(name, cond, detail = "") {
  if (cond) {
    pass++;
    console.log(`  PASS  ${name}`);
  } else {
    fail++;
    console.log(`  FAIL  ${name}${detail ? ` -- ${detail}` : ""}`);
  }
}

// Derived from the Worker's own manifest rather than hardcoded, so tagging a
// new release does not break this suite. The property under test is not
// "digest X is served" but "the bytes served hash to whatever the Worker
// advertises" — that must hold at every version, forever.
const bootstrap = JSON.parse(await (await call("/manifest.json")).text());
const LATEST = bootstrap.version;
const LATEST_COMMIT = bootstrap.commit;
const EXPECTED_SH = bootstrap.artifacts["install.sh"].sha256;

async function digestOf(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

console.log("\n== happy path ==");
{
  const r = await call("/");
  const body = await r.text();
  check("GET / -> 200", r.status === 200, `got ${r.status}`);
  // ?? "" because a missing content-type would throw on .includes() and abort
  // the whole suite with a TypeError, reporting a crash instead of the failed
  // assertion that actually matters. Every other header check here uses === or
  // RegExp.test, both of which already tolerate null.
  check(
    "content-type is shellscript",
    (r.headers.get("content-type") ?? "").includes("x-shellscript"),
    r.headers.get("content-type") ?? "(absent)",
  );
  check("body is the installer", body.startsWith("#!/bin/sh"));
  check("served bytes match advertised digest", (await digestOf(body)) === EXPECTED_SH);
  check("x-resq-sha256 header correct", r.headers.get("x-resq-sha256") === EXPECTED_SH);
  check("nosniff set", r.headers.get("x-content-type-options") === "nosniff");
  check("CSP set", r.headers.get("content-security-policy") === "default-src 'none'; sandbox");
  check("latest is short-cached", r.headers.get("cache-control") === "public, max-age=300");
  check("commit pinned in header", /^[0-9a-f]{40}$/.test(r.headers.get("x-resq-commit")));
}

console.log("\n== versioned + aliases ==");
{
  const r = await call(`/${LATEST}/install.sh`);
  check(`GET /${LATEST}/install.sh -> 200`, r.status === 200);
  check(
    "versioned is immutable-cached",
    r.headers.get("cache-control") === "public, max-age=31536000, immutable",
  );
  const v = await call(`/v${LATEST}/install.sh`);
  check("leading v tolerated", v.status === 200);
  const a = await call("/install-hooks.sh");
  check("repo-basename alias resolves", a.status === 200);
  const h = await call("/hooks.sh");
  check("short name resolves", h.status === 200);
  const p = await call("/install.ps1");
  check("ps1 served", p.status === 200 && (await p.text()).length > 0);
}

console.log("\n== generated documents ==");
{
  // How many artifacts this release actually carries, rather than a fixed 6 —
  // older tags predate some scripts and legitimately publish fewer.
  const published = Object.values(bootstrap.artifacts).filter((a) => a.sha256).length;
  const s = await call("/SHA256SUMS");
  const body = await s.text();
  check("SHA256SUMS -> 200", s.status === 200);
  check("one line per published artifact", body.trim().split("\n").length === published, body);
  check("sha256sum -c format", /^[0-9a-f]{64} {2}install\.sh$/m.test(body));
  const m = await call("/manifest.json");
  const json = JSON.parse(await m.text());
  check("manifest parses", json.version === LATEST && json.commit.length === 40);
  check("every published digest is well formed", Object.values(bootstrap.artifacts)
    .filter((a) => a.sha256)
    .every((a) => /^[0-9a-f]{64}$/.test(a.sha256)));
}

console.log("\n== fail closed ==");
{
  // Real commit, deliberately wrong digest -> must refuse to serve.
  const tampered = JSON.stringify({
    latest: LATEST,
    releases: {
      [LATEST]: {
        commit: LATEST_COMMIT,
        artifacts: { "install.sh": "0".repeat(64) },
      },
    },
  });
  const r = await call("/install.sh", {}, { RESQ_PINS: tampered });
  const body = await r.text();
  check("digest mismatch -> 502", r.status === 502, `got ${r.status}`);
  check("no installer bytes leaked", !body.includes("SCRIPT_VERSION"), body.slice(0, 80));
  check("error body is inert shell", body.startsWith("#!/bin/sh") && body.includes("exit 1"));
  check("errors not cached", r.headers.get("cache-control") === "no-store");
}
{
  // Malformed override must fall back to inline pins, never to unverified.
  const r = await call("/install.sh", {}, { RESQ_PINS: "{ not json" });
  check("malformed RESQ_PINS falls back to known-good", r.status === 200);
  const r2 = await call("/install.sh", {}, { RESQ_PINS: '{"latest":"9.9.9","releases":{}}' });
  check("shape-invalid RESQ_PINS falls back", r2.status === 200);
}

console.log("\n== rejected requests ==");
{
  const cases = [
    ["/nope.sh", 404, "unknown artifact"],
    ["/9.9.9/install.sh", 404, "unknown version"],
    ["/a/b/c/install.sh", 404, "too deep"],
    ["/..%2F..%2Fetc%2Fpasswd", 404, "encoded traversal"],
    ["/../../../../etc/passwd", 404, "raw traversal"],
    ["/scripts/install-hooks.sh", 404, "repo path is not a route"],
  ];
  for (const [path, want, label] of cases) {
    const r = await call(path);
    check(`${label} -> ${want}`, r.status === want, `${path} got ${r.status}`);
  }
  const post = await call("/", { method: "POST" });
  check("POST -> 405", post.status === 405);
  check("405 advertises Allow", post.headers.get("allow") === "GET, HEAD");
  const del = await call("/install.sh", { method: "DELETE" });
  check("DELETE -> 405", del.status === 405);
}

console.log("\n== conditional + HEAD ==");
{
  const head = await call("/", { method: "HEAD" });
  check("HEAD -> 200", head.status === 200);
  check("HEAD has empty body", (await head.text()) === "");
  check("HEAD keeps digest header", head.headers.get("x-resq-sha256") === EXPECTED_SH);
  const cond = await call("/", { headers: { "if-none-match": `"${EXPECTED_SH}"` } });
  check("matching ETag -> 304", cond.status === 304);
  const stale = await call("/", { headers: { "if-none-match": '"deadbeef"' } });
  check("stale ETag -> 200", stale.status === 200);
}

console.log("\n== survives without the Cache API ==");
{
  // This shipped once. An unguarded `caches.default` throws a ReferenceError
  // when Cache is disabled in the Worker's runtime settings, so every artifact
  // route 500'd while /manifest.json — which needs no cache — kept answering,
  // making the deploy look healthy. Caching is an optimisation; what we serve
  // must not depend on it.
  const saved = globalThis.caches;
  // eslint-disable-next-line no-delete-var
  delete globalThis.caches;
  try {
    const r = await call("/");
    const body = await r.text();
    check("no Cache API -> still 200", r.status === 200, `got ${r.status}`);
    check("no Cache API -> correct bytes", (await digestOf(body)) === EXPECTED_SH);
    const h = await call("/hooks.sh");
    check("no Cache API -> hooks.sh 200", h.status === 200, `got ${h.status}`);
  } finally {
    globalThis.caches = saved;
  }
}

console.log("\n== unhandled errors stay inert ==");
{
  // A throw escaping the handler becomes a runtime 500 whose body is the host's
  // HTML error page — which a `curl | sh` would execute. Every deliberate
  // failure path returns shell that exits 1; the accidental one must too.
  const realDigest = crypto.subtle.digest.bind(crypto.subtle);
  crypto.subtle.digest = () => {
    throw new Error("synthetic failure");
  };
  let status, body, cacheControl;
  try {
    const r = await call("/");
    status = r.status;
    cacheControl = r.headers.get("cache-control");
    body = await r.text();
  } finally {
    crypto.subtle.digest = realDigest;
  }
  check("internal throw -> 500", status === 500, `got ${status}`);
  check("internal throw -> inert shell", body.startsWith("#!/bin/sh") && body.includes("exit 1"));
  check("internal throw -> not HTML", !body.includes("<html"), body.slice(0, 40));
  check("internal throw -> not cached", cacheControl === "no-store");
  check("internal throw -> leaks no installer bytes", !body.includes("SCRIPT_VERSION"));
}

console.log(`\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
