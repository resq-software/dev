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

// Imported as .ts directly. Node strips types natively (23.6+), so the tests
// exercise the same file Wrangler bundles — no build step, and no compiled
// copy that could drift from the source under review.
const mod = await import("../src/index.ts");
const { createHandler, validatePinConfig, DEFAULT_PINS } = mod;
const worker = mod.default;

const ctx = { waitUntil: (p) => p.catch(() => {}) };
const call = (path, init = {}) =>
  worker.fetch(new Request(`https://get.resq.software${path}`, init), {}, ctx);

// Drive a handler built over a specific pin set. This replaces the RESQ_PINS
// environment override, which existed only so tests could inject bad pins and
// was, in production, an unreviewed way to repoint the installer. Same code
// path — createHandler is what the default export is built from — with no
// bypass left in the deployed Worker.
const callWith = (pins, path, init = {}) =>
  createHandler(pins).fetch(new Request(`https://get.resq.software${path}`, init), {}, ctx);

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
  //
  // Injected by constructing a handler, not through an environment variable.
  // The pins below are structurally valid — 64 hex characters, just not the
  // right ones — so this exercises the byte comparison in verifiedFetch rather
  // than the shape validation.
  const tampered = {
    latest: LATEST,
    releases: {
      [LATEST]: {
        commit: LATEST_COMMIT,
        artifacts: { "install.sh": "0".repeat(64) },
      },
    },
  };
  const r = await callWith(tampered, "/install.sh");
  const body = await r.text();
  check("digest mismatch -> 502", r.status === 502, `got ${r.status}`);
  check("no installer bytes leaked", !body.includes("SCRIPT_VERSION"), body.slice(0, 80));
  check("error body is inert shell", body.startsWith("#!/bin/sh") && body.includes("exit 1"));
  check("errors not cached", r.headers.get("cache-control") === "no-store");
}
{
  // validatePinConfig is now the whole contract for "is this a usable pin set".
  // These assert it directly rather than inferring it from HTTP status codes.
  // With the RESQ_PINS override gone there is no untrusted pin set at runtime,
  // so the property worth testing is the validator itself — it is what CI runs
  // over the inline PINS, and what any caller of createHandler should run first.
  check("a non-object is rejected", validatePinConfig("{ not json") === null);
  check("null is rejected", validatePinConfig(null) === null);
  check("an array is rejected", validatePinConfig([]) === null);
  check("latest naming no release is rejected", validatePinConfig({ latest: "9.9.9", releases: {} }) === null);

  // `latest` naming a prototype key must not resolve through Object.prototype.
  check("__proto__ as latest is rejected", validatePinConfig({ latest: "__proto__", releases: {} }) === null);

  // EVERY release is validated, not only releases[latest]. The regression this
  // guards: a second release riding along with a commit never checked to be a
  // 40-hex SHA — i.e. possibly a branch or tag, which move.
  const mutableRef = {
    latest: LATEST,
    releases: {
      [LATEST]: { commit: LATEST_COMMIT, artifacts: { "install.sh": "0".repeat(64) } },
      "9.9.9": { commit: "main", artifacts: { "install.sh": "0".repeat(64) } },
    },
  };
  check("a non-SHA commit in ANY release rejects the whole set", validatePinConfig(mutableRef) === null);

  check(
    "a malformed digest rejects the whole set",
    validatePinConfig({
      latest: LATEST,
      releases: { [LATEST]: { commit: LATEST_COMMIT, artifacts: { "install.sh": "not-a-digest" } } },
    }) === null,
  );

  // A fully valid set must be ACCEPTED. Without this the suite would pass just
  // as well if validatePinConfig rejected everything, which would look like
  // hardening while actually being broken.
  const artifacts = Object.fromEntries(
    Object.values(bootstrap.artifacts)
      .filter((a) => a.sha256)
      .map((a) => [a.path, a.sha256]),
  );
  const valid = { latest: LATEST, releases: { [LATEST]: { commit: LATEST_COMMIT, artifacts } } };
  check("a valid pin set is accepted", validatePinConfig(valid) !== null);

  // ...and serves real bytes through the same code path production uses.
  const r = await callWith(valid, "/install.sh");
  const body = await r.text();
  check("a validated set serves the pinned bytes", r.status === 200 && body.includes("SCRIPT_VERSION"), `got ${r.status}`);

  // The documented usage for an untrusted set: validate, else fall back.
  const fallback = createHandler(validatePinConfig(mutableRef) ?? DEFAULT_PINS);
  const fb = await fallback.fetch(new Request("https://get.resq.software/9.9.9/install.sh"), {}, ctx);
  check("validate-or-fall-back yields the inline pins", fb.status === 404, `got ${fb.status}`);
}
{
  // The override is gone: passing one has no effect, because nothing reads it.
  const r = await worker.fetch(
    new Request("https://get.resq.software/install.sh"),
    { RESQ_PINS: JSON.stringify({ latest: "9.9.9", releases: {} }) },
    ctx,
  );
  check("a stray RESQ_PINS env value is ignored entirely", r.status === 200, `got ${r.status}`);
}

console.log("\n== review findings ==");
{
  // The inline pins must satisfy the validator. They used to be exempt: the old
  // pins() returned DEFAULT_PINS unexamined, so the 40-hex commit rule and the
  // "latest names a real release" rule applied only to the untrusted path —
  // backwards from where belt-and-braces belongs. Checked here rather than at
  // module scope on purpose: a throw during module init would take the endpoint
  // down, while this fails the build before anything deploys.
  //
  // This is also what backs the single `as PinConfig` assertion on DEFAULT_PINS.
  // The compiler checks the shape; this checks that the strings are really hex.
  check("inline PINS satisfy validatePinConfig", validatePinConfig(DEFAULT_PINS) !== null);
  check(
    "inline PINS.latest names a real release",
    Object.hasOwn(DEFAULT_PINS.releases, DEFAULT_PINS.latest),
    DEFAULT_PINS.latest,
  );
  const badCommits = Object.entries(DEFAULT_PINS.releases)
    .filter(([, r]) => !/^[0-9a-f]{40}$/.test(r.commit))
    .map(([v]) => v);
  check("every inline commit is a 40-hex SHA, not a branch or tag", badCommits.length === 0, badCommits.join(","));
}
{
  // The top-level catch classified by full URL, so a query string moved an
  // artifact into the wrong body format: /install.ps1?v=1 does not end in
  // ".ps1", so a PowerShell client was handed a #!/bin/sh body.
  const realDigest = crypto.subtle.digest;
  let psStatus, psBody, shBody;
  try {
    crypto.subtle.digest = () => {
      throw new Error("synthetic failure");
    };
    const ps = await call("/install.ps1?v=1");
    psStatus = ps.status;
    psBody = await ps.text();
    shBody = await (await call("/install.sh?x=.json")).text();
  } finally {
    crypto.subtle.digest = realDigest;
  }
  check("throw on .ps1?query -> 500", psStatus === 500, `got ${psStatus}`);
  check("throw on .ps1?query -> NOT a shell body", !psBody.startsWith("#!/bin/sh"), psBody.slice(0, 30));
  check("throw on .sh?x=.json -> still inert shell", shBody.startsWith("#!/bin/sh"), shBody.slice(0, 30));
}
{
  // 405 obeys the "shell routes get inert shell bodies" rule too.
  const r = await call("/install.sh", { method: "POST" });
  const body = await r.text();
  check("POST /install.sh -> 405", r.status === 405, `got ${r.status}`);
  check("405 allow header", r.headers.get("allow") === "GET, HEAD");
  check("405 on a shell route is inert shell", body.startsWith("#!/bin/sh") && body.includes("exit 1"));
  const rp = await call("/install.ps1", { method: "POST" });
  check("405 on a .ps1 route is not shell", !(await rp.text()).startsWith("#!/bin/sh"));
}
{
  // SHA256SUMS must name artifacts the way clients receive them, or
  // `sha256sum -c` fails on the filename for every route whose repo path
  // differs — which is all of them except install.sh and install.ps1.
  const sums = await (await call("/SHA256SUMS")).text();
  const names = sums.trim().split("\n").map((l) => l.split(/\s+/)[1]);
  check("SHA256SUMS names routes, not repo paths", names.includes("hooks.sh"), names.join(" "));
  check("SHA256SUMS has no repo paths left", !names.some((n) => n.includes("/")), names.join(" "));
  check("SHA256SUMS is sha256sum -c shaped", /^[0-9a-f]{64} {2}\S+$/.test(sums.trim().split("\n")[0]));
  check("SHA256SUMS ends with a newline", sums.endsWith("\n"));
}
{
  // Alias parity: hooks.sh had a repo-basename alias, hooks.ps1 did not.
  const r = await call("/install-hooks.ps1");
  check("install-hooks.ps1 alias resolves", r.status === 200, `got ${r.status}`);
  check("alias serves a non-empty artifact", (await r.text()).length > 0);
}
{
  // Conditional requests: weak tags and comma-separated lists are valid
  // If-None-Match syntax and were previously missed, costing a full body.
  const first = await call("/install.sh");
  const etag = first.headers.get("etag");
  const strong = await call("/install.sh", { headers: { "if-none-match": etag } });
  check("exact etag -> 304", strong.status === 304, `got ${strong.status}`);
  check("304 carries cache-control", !!strong.headers.get("cache-control"), "missing");
  const weak = await call("/install.sh", { headers: { "if-none-match": `W/${etag}` } });
  check("weak etag -> 304", weak.status === 304, `got ${weak.status}`);
  const list = await call("/install.sh", { headers: { "if-none-match": `"other", ${etag}` } });
  check("etag in a list -> 304", list.status === 304, `got ${list.status}`);
  const star = await call("/install.sh", { headers: { "if-none-match": "*" } });
  check("* -> 304", star.status === 304, `got ${star.status}`);
  const miss = await call("/install.sh", { headers: { "if-none-match": '"nope"' } });
  check("non-matching etag -> 200", miss.status === 200, `got ${miss.status}`);
}
{
  // content-length is a HEAD-only claim now: on GET the runtime owns framing.
  const head = await call("/install.sh", { method: "HEAD" });
  check("HEAD reports content-length", !!head.headers.get("content-length"));
  check("HEAD has no body", (await head.text()) === "");
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
