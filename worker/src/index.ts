/**
 * get.resq.software — pinned, hash-verified distribution for ResQ installers.
 *
 * Copyright 2026 ResQ Software
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ── Threat model ───────────────────────────────────────────────────────────
 *
 * This endpoint exists to be piped into a shell. That makes it a remote code
 * execution primitive by design, so the only meaningful question is: whose
 * code, exactly?
 *
 * Three properties answer that:
 *
 *   1. IMMUTABLE UPSTREAM. We fetch by 40-char commit SHA, never by branch or
 *      tag. Branches move on every push; tags can be force-moved by anyone
 *      with write access. A commit SHA cannot be repointed.
 *
 *   2. CONTENT VERIFICATION, FAIL CLOSED. Every byte is SHA-256'd and compared
 *      against a digest baked in at deploy time, before any of it reaches the
 *      client. If GitHub is compromised, or a proxy tampers in transit, or the
 *      pin is stale, the request 502s having served nothing. There is no
 *      degraded mode that serves unverified bytes.
 *
 *   3. NO RUNTIME TRUST IN GITHUB. The expected digests travel with the
 *      deploy, not with the response. GitHub supplies bytes; it does not get
 *      to say whether those bytes are correct.
 *
 * Corollary: bumping the installer is a deliberate, reviewable act — edit
 * PINS, deploy. It can no longer happen as a side effect of pushing to main.
 *
 * ── A note on types ────────────────────────────────────────────────────────
 *
 * Types here are a maintainability tool, not a security control, and it is
 * worth being honest about that: neither of this Worker's two production
 * outages would have been caught by the compiler. `caches` is declared in
 * @cloudflare/workers-types, so the missing-binding ReferenceError typechecked
 * fine; and `redirect: "error"` is valid in the standard RequestInit, so the
 * call workerd rejects at runtime is the one TypeScript approves. Both were
 * runtime divergences from the type definitions. The tests and the live
 * monitor catch those; the compiler does not.
 *
 * ── Using it ───────────────────────────────────────────────────────────────
 *
 *   curl -fsSL https://get.resq.software | sh
 *
 * Verify by hand at any time:
 *
 *   curl -fsSL https://get.resq.software/SHA256SUMS
 *   curl -fsSL https://get.resq.software/install.sh | sha256sum
 *   curl -fsSI https://get.resq.software | grep x-resq-sha256
 */

// ── Types ───────────────────────────────────────────────────────────────────

export interface Release {
  commit: string;
  artifacts: Record<string, string>;
}

export interface PinConfig {
  latest: string;
  releases: Record<string, Release>;
}

export interface Env {
  /** Optional wholesale pin override, same JSON shape as PINS. */
  RESQ_PINS?: string;
}

interface ArtifactMeta {
  path: string;
  type: string;
  /** Whether a failure body for this route must itself be inert shell. */
  shell: boolean;
}

interface RouteTarget {
  version: string | null;
  name: string;
}

// ── Pin set ─────────────────────────────────────────────────────────────────
//
// The trust anchor. `commit` is what is actually fetched; `version` is only a
// human label for it. Digests are of the raw blob at that commit, which is
// byte-identical to what raw.githubusercontent.com serves.
//
// To regenerate after tagging a release:
//
//   C=$(git rev-parse origin/main)
//   for f in install.sh install.ps1 scripts/install-hooks.sh \
//            scripts/install-resq.sh scripts/setup.sh scripts/setup.ps1; do
//     printf '%s  %s\n' "$(git cat-file blob "$C:$f" | sha256sum | cut -d' ' -f1)" "$f"
//   done
//
// CI can override this wholesale via the RESQ_PINS var (same JSON shape) so a
// release deploy never has to rewrite source. A malformed override falls back
// to the inline pins below — degrading to a known-good pin, never to unpinned.
//
// DELIBERATELY UNANNOTATED. bin/gen-pins.sh rewrites this block by text
// surgery: it locates `^const PINS = {`, finds the closing `^};`, and emits
// `const PINS = <json>;`. A `: PinConfig` annotation or a trailing `satisfies`
// clause would either be silently discarded on the next --write or break the
// closing-brace match outright. The type is applied on the line after the
// block instead, which the generator never touches — so the generated JSON is
// still checked against PinConfig at compile time.

const PINS = {
  "latest": "0.4.2",
  "releases": {
    "0.4.0": {
      "commit": "228b73de77d2e20a3d7a2e7137e508de9e602f16",
      "artifacts": {
        "install.sh": "639b4167471082c6e59084a57e4e535e6ceef09909888873fa5f0ac39efc13be",
        "install.ps1": "188e0979c3eca059f18a6553f56d6ec195948d78b899babc142f19249a6a586c",
        "scripts/install-hooks.sh": "24bd874dd27ff55153be602a5ad7fb366f4283ae4423323f8fd2bc2af442c68a",
        "scripts/install-hooks.ps1": "4976c3920f5e2c5e6d347ed791d00119f46152c946a6f8186a98690deef9dd23",
        "scripts/install-resq.sh": "38a70c003b3b83f8cf5e78961fea1246b69247a800fc1788167e5b4ea44759bf",
        "scripts/setup.sh": "6792ee2e02bcfa982046a36ed68532f4af44be93fd1243fc77a253d303767ca1",
        "scripts/setup.ps1": "899a4840661be11ab3104e1aca60f3bfb78f8a7139bf6a373803d6c1c0a8db55"
      }
    },
    "0.4.1": {
      "commit": "55e1928c005b1b13ed121e7d6437e3721e53952c",
      "artifacts": {
        "install.sh": "2a25701001325530d1575b18f858b1e1841c0d89bba737e6a5ff3ff559710dea",
        "install.ps1": "98c667397929ea16d11b29b15c5db0d60604a9bb805f82423aee907c0308c73e",
        "scripts/install-hooks.sh": "3b3e67197ffe8df9b4b4df1088c8e0fa5a737d69f18a5d97bc36bd697762c3e2",
        "scripts/install-hooks.ps1": "772ee7538f585effdc809a9a760314b4261b5c0955897e844db6d020c0fbed5e",
        "scripts/install-resq.sh": "38a70c003b3b83f8cf5e78961fea1246b69247a800fc1788167e5b4ea44759bf",
        "scripts/setup.sh": "6792ee2e02bcfa982046a36ed68532f4af44be93fd1243fc77a253d303767ca1",
        "scripts/setup.ps1": "899a4840661be11ab3104e1aca60f3bfb78f8a7139bf6a373803d6c1c0a8db55"
      }
    },
    "0.4.2": {
      "commit": "a66d8743be13db8c84d417451825133ea0fa2275",
      "artifacts": {
        "install.sh": "f121913c2b5bcf29fb3dc6035cd8a65c4b72272fa33f41dc30b9f1c63bc3f17c",
        "install.ps1": "84bc0151326545092da50bc650d64ef5e0fbce4052106c363643195c52eab4a7",
        "scripts/install-hooks.sh": "3b3e67197ffe8df9b4b4df1088c8e0fa5a737d69f18a5d97bc36bd697762c3e2",
        "scripts/install-hooks.ps1": "772ee7538f585effdc809a9a760314b4261b5c0955897e844db6d020c0fbed5e",
        "scripts/install-resq.sh": "38a70c003b3b83f8cf5e78961fea1246b69247a800fc1788167e5b4ea44759bf",
        "scripts/setup.sh": "6792ee2e02bcfa982046a36ed68532f4af44be93fd1243fc77a253d303767ca1",
        "scripts/setup.ps1": "899a4840661be11ab3104e1aca60f3bfb78f8a7139bf6a373803d6c1c0a8db55"
      }
    }
  }
};

// The type check on the generated block. If gen-pins.sh ever emits something
// structurally wrong — a missing commit, artifacts as an array — this line
// fails to compile.
const DEFAULT_PINS: PinConfig = PINS;

const REPO = "resq-software/dev";

// Cap well above the largest artifact (install.ps1, ~27 KB) and far below any
// size that could pressure Worker memory. Enforced while streaming, so a
// missing or lying content-length cannot get around it.
const MAX_BYTES = 1024 * 1024;

const SHELL = "text/x-shellscript; charset=utf-8";
const PWSH = "text/plain; charset=utf-8";

// Public route name -> repo path. Routes resolve through this table, so a
// request path is never interpolated into the upstream URL. Path traversal is
// structurally impossible rather than filtered.
const ARTIFACTS: Record<string, ArtifactMeta> = {
  "install.sh": { path: "install.sh", type: SHELL, shell: true },
  "install.ps1": { path: "install.ps1", type: PWSH, shell: false },
  "hooks.sh": { path: "scripts/install-hooks.sh", type: SHELL, shell: true },
  "hooks.ps1": { path: "scripts/install-hooks.ps1", type: PWSH, shell: false },
  "resq.sh": { path: "scripts/install-resq.sh", type: SHELL, shell: true },
  "setup.sh": { path: "scripts/setup.sh", type: SHELL, shell: true },
  "setup.ps1": { path: "scripts/setup.ps1", type: PWSH, shell: false },
};

// Accept the repo basename too, so a URL copied out of the repo still works.
const ALIASES: Record<string, string> = {
  "install-hooks.sh": "hooks.sh",
  "install-resq.sh": "resq.sh",
};

// ── Helpers ─────────────────────────────────────────────────────────────────

function pins(env: Env | undefined): PinConfig {
  if (!env || typeof env.RESQ_PINS !== "string") return DEFAULT_PINS;
  try {
    const parsed = JSON.parse(env.RESQ_PINS) as Partial<PinConfig>;
    // Validate the shape before trusting it. A half-formed override that
    // slipped through a bad deploy must not disable verification.
    //
    // Typed as Partial and probed field by field on purpose: JSON.parse returns
    // `any`, and a bare `as PinConfig` would have the compiler vouch for a
    // shape nothing actually checked. The runtime guards are the real control
    // here, exactly as before.
    const latest = parsed?.latest;
    if (typeof latest !== "string") return DEFAULT_PINS;
    const rel = parsed?.releases?.[latest];
    if (!rel || !/^[0-9a-f]{40}$/.test(rel.commit ?? "")) return DEFAULT_PINS;
    if (!rel.artifacts || typeof rel.artifacts !== "object") return DEFAULT_PINS;
    return parsed as PinConfig;
  } catch {
    return DEFAULT_PINS;
  }
}

function hex(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let out = "";
  // for..of rather than an index loop: identical output, and it does not trip
  // noUncheckedIndexedAccess.
  for (const byte of bytes) out += byte.toString(16).padStart(2, "0");
  return out;
}

async function sha256Hex(bytes: Uint8Array | ArrayBuffer): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", bytes as BufferSource));
}

// Length-independent comparison. These digests are public so timing is not a
// real oracle, but comparing this way costs nothing and keeps the habit.
function digestsEqual(a: string | undefined, b: string | undefined): boolean {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Read a body with a hard ceiling, enforced as chunks arrive. Returns null if
// the cap is exceeded so the caller can fail closed.
async function readCapped(response: Response, max: number): Promise<Uint8Array | null> {
  const declared = response.headers.get("content-length");
  if (declared !== null && Number(declared) > max) return null;
  if (!response.body) return null;

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

// Error bodies for shell routes are themselves valid shell that exits nonzero.
// `curl -fsSL` suppresses error bodies, but people drop -f, and a bare English
// sentence piped into sh is a command. This makes the failure mode inert.
// Messages come from a fixed set — no request data is ever reflected.
function errorBody(message: string, asShell: boolean): string {
  if (!asShell) return `resq: ${message}\n`;
  return `#!/bin/sh\n# resq installer: ${message}\nprintf '%s\\n' 'resq installer: ${message}' >&2\nexit 1\n`;
}

function baseHeaders(): Record<string, string> {
  return {
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; sandbox",
    "referrer-policy": "no-referrer",
    "cross-origin-resource-policy": "same-origin",
    "x-frame-options": "DENY",
    "strict-transport-security": "max-age=63072000; includeSubDomains; preload",
  };
}

function errorResponse(status: number, message: string, asShell: boolean): Response {
  return new Response(errorBody(message, asShell), {
    status,
    headers: {
      ...baseHeaders(),
      "content-type": asShell ? SHELL : "text/plain; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

// ── Routing ─────────────────────────────────────────────────────────────────

// Shapes accepted:
//   /                        -> latest install.sh
//   /install.sh              -> latest, by name
//   /0.3.0/install.sh        -> pinned to that release
//   /v0.3.0/install.sh       -> same, leading v tolerated
//   /SHA256SUMS              -> digest manifest, sha256sum -c format
//   /manifest.json           -> full pin metadata
// Anything deeper, or any unknown name, is a 404.
function route(pathname: string): RouteTarget | null {
  const parts = pathname.split("/").filter(Boolean);

  if (parts.length === 0) return { version: null, name: "install.sh" };
  if (parts.length > 2) return null;

  let version: string | null = null;
  // Read through locals rather than indexing twice: a length check does not
  // narrow element types under noUncheckedIndexedAccess, and an explicit
  // undefined check is clearer than a non-null assertion.
  const first = parts[0];
  if (first === undefined) return null;
  let name = first;
  if (parts.length === 2) {
    const second = parts[1];
    if (second === undefined) return null;
    version = first.replace(/^v/, "");
    name = second;
  }

  if (name === "SHA256SUMS" || name === "manifest.json") return { version, name };

  const canonical = ALIASES[name] ?? name;
  if (!Object.prototype.hasOwnProperty.call(ARTIFACTS, canonical)) return null;
  return { version, name: canonical };
}

// ── Fetch + verify ──────────────────────────────────────────────────────────

// Returns verified bytes, or null if anything at all was off. Verified bodies
// are cached by commit+path, so the digest is computed once per artifact per
// edge rather than once per request.
// The Cache API is an optimisation and nothing more, so every use of it is
// guarded. It can be genuinely absent: a Worker with Cache disabled in its
// runtime settings has no `caches` binding at all, and merely referencing it
// throws a ReferenceError. An earlier version of this file assumed it was
// always present, which turned "cache unavailable" into an unhandled exception
// and a 500 on every artifact route, while /manifest.json — which needs no
// cache — kept working and made the Worker look healthy.
//
// The compiler is no help here: workers-types declares `caches`, so the version
// that crashed typechecked cleanly. These guards stay because the runtime, not
// the type, decides.
async function cacheMatch(key: Request): Promise<Response | undefined> {
  try {
    if (typeof caches === "undefined" || !caches.default) return undefined;
    return await caches.default.match(key);
  } catch {
    return undefined;
  }
}

function cachePut(ctx: ExecutionContext, key: Request, response: Response): void {
  try {
    if (typeof caches === "undefined" || !caches.default) return;
    // put() can throw synchronously, which would escape ctx.waitUntil and fail
    // the request — hence the surrounding try, not merely a .catch().
    ctx.waitUntil(caches.default.put(key, response).catch(() => {}));
  } catch {
    /* best-effort only; never let caching change what we serve */
  }
}

async function verifiedFetch(
  commit: string,
  repoPath: string,
  expectedDigest: string,
  ctx: ExecutionContext,
): Promise<Uint8Array | null> {
  const cacheKey = new Request(`https://pin.resq.internal/${commit}/${repoPath}`);

  const cached = await cacheMatch(cacheKey);
  if (cached) {
    const bytes = new Uint8Array(await cached.arrayBuffer());
    // Re-verify on the way out of cache. Cheap, and it means a poisoned or
    // truncated cache entry can never be served.
    if (digestsEqual(await sha256Hex(bytes), expectedDigest)) return bytes;
  }

  // Staged so a failure names the stage it happened in. The first version of
  // this function let anything unexpected propagate, which surfaced as an
  // opaque 500 with no way to tell a network problem from a bad digest. Every
  // stage now fails closed to null, which the caller turns into a 502.
  let bytes: Uint8Array | null;
  try {
    const upstream = await fetch(
      `https://raw.githubusercontent.com/${REPO}/${commit}/${repoPath}`,
      {
        cf: { cacheTtl: 3600, cacheEverything: true },
        headers: { "user-agent": "get.resq.software" },
        // "manual", not "error". Workers' fetch() rejects redirect: "error",
        // which throws on every subrequest rather than only on a redirect —
        // Node accepts it, so local tests passed while production 500'd. A
        // redirect from a pinned commit URL would itself be suspicious, so it
        // is treated as a failure explicitly below.
        //
        // TypeScript will not stop anyone repeating this: "error" is a valid
        // RequestRedirect in the standard lib types. Only workerd objects.
        redirect: "manual",
      },
    );

    if (upstream.status >= 300 && upstream.status < 400) {
      console.error(JSON.stringify({ event: "upstream_redirect", commit, path: repoPath, status: upstream.status }));
      return null;
    }
    if (!upstream.ok) {
      console.error(JSON.stringify({ event: "upstream_status", commit, path: repoPath, status: upstream.status }));
      return null;
    }

    bytes = await readCapped(upstream, MAX_BYTES);
    if (bytes === null) {
      console.error(JSON.stringify({ event: "upstream_too_large", commit, path: repoPath }));
      return null;
    }
  } catch (err) {
    console.error(
      JSON.stringify({
        event: "upstream_fetch_threw",
        commit,
        path: repoPath,
        message: String(err instanceof Error ? err.message : err),
      }),
    );
    return null;
  }

  if (!digestsEqual(await sha256Hex(bytes), expectedDigest)) return null;

  cachePut(
    ctx,
    cacheKey,
    new Response(bytes as BodyInit, { headers: { "cache-control": "public, max-age=86400" } }),
  );
  return bytes;
}

// ── Generated documents ─────────────────────────────────────────────────────

function sha256sums(release: Release): string {
  return (
    Object.entries(release.artifacts)
      .sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([path, digest]) => `${digest}  ${path}`)
      .join("\n") + "\n"
  );
}

function manifest(config: PinConfig, version: string, release: Release): string {
  return (
    JSON.stringify(
      {
        repository: `github:${REPO}`,
        version,
        latest: config.latest,
        commit: release.commit,
        source: `https://github.com/${REPO}/tree/${release.commit}`,
        artifacts: Object.fromEntries(
          Object.entries(ARTIFACTS).map(([name, meta]) => [
            name,
            { path: meta.path, sha256: release.artifacts[meta.path] ?? null },
          ]),
        ),
        versions: Object.keys(config.releases).sort(),
      },
      null,
      2,
    ) + "\n"
  );
}

// ── Entry point ─────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // Any exception escaping here becomes a runtime 500 whose body is
    // Cloudflare's HTML error page — which is exactly what someone's `curl | sh`
    // would then execute. Every deliberate failure path in this file returns an
    // inert shell body precisely to avoid that, so an unhandled throw must not
    // be the one route that bypasses it.
    try {
      return await handle(request, env, ctx);
    } catch (err) {
      console.error(
        JSON.stringify({
          event: "unhandled_error",
          message: String(err instanceof Error ? err.message : err),
        }),
      );
      const asShell = !request.url.endsWith(".ps1") && !request.url.endsWith(".json");
      return errorResponse(500, "internal error - refusing to serve", asShell);
    }
  },
} satisfies ExportedHandler<Env>;

async function handle(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url);
  const isShellPath = !url.pathname.endsWith(".ps1") && !url.pathname.endsWith(".json");

  if (request.method !== "GET" && request.method !== "HEAD") {
    const res = errorResponse(405, "method not allowed", false);
    res.headers.set("allow", "GET, HEAD");
    return res;
  }

  const target = route(url.pathname);
  if (!target) return errorResponse(404, "not found", isShellPath);

  const config = pins(env);
  const version = target.version ?? config.latest;
  const release = Object.prototype.hasOwnProperty.call(config.releases, version)
    ? config.releases[version]
    : undefined;
  if (!release) return errorResponse(404, "unknown version", isShellPath);

  // Generated documents: derived from the pins, nothing to fetch or verify.
  if (target.name === "SHA256SUMS" || target.name === "manifest.json") {
    const isJson = target.name === "manifest.json";
    const body = isJson ? manifest(config, version, release) : sha256sums(release);
    return new Response(request.method === "HEAD" ? null : body, {
      headers: {
        ...baseHeaders(),
        "content-type": isJson ? "application/json; charset=utf-8" : "text/plain; charset=utf-8",
        "cache-control": target.version
          ? "public, max-age=31536000, immutable"
          : "public, max-age=300",
        "x-resq-version": version,
        "x-resq-commit": release.commit,
      },
    });
  }

  const meta = ARTIFACTS[target.name];
  // route() only returns names present in ARTIFACTS, so this is unreachable —
  // but the lookup is typed as possibly-undefined, and a 404 is the honest
  // answer if that invariant is ever broken by an edit.
  if (!meta) return errorResponse(404, "not found", isShellPath);

  const expected = release.artifacts[meta.path];
  if (!expected) return errorResponse(404, "artifact not in this release", meta.shell);

  // A matching ETag means the client already holds these exact bytes, and
  // the ETag *is* the content digest — so this is a safe short-circuit.
  const etag = `"${expected}"`;
  if (request.headers.get("if-none-match") === etag) {
    return new Response(null, { status: 304, headers: { etag, ...baseHeaders() } });
  }

  const bytes = await verifiedFetch(release.commit, meta.path, expected, ctx);
  if (bytes === null) {
    // Deliberately uninformative: the client cannot tell a digest mismatch
    // from an upstream outage, and does not need to. Either way nothing is
    // served. Operators get the detail in the log.
    console.error(
      JSON.stringify({
        event: "verification_failed",
        commit: release.commit,
        path: meta.path,
        expected,
      }),
    );
    return errorResponse(502, "could not verify installer - refusing to serve", meta.shell);
  }

  return new Response(request.method === "HEAD" ? null : (bytes as BodyInit), {
    headers: {
      ...baseHeaders(),
      "content-type": meta.type,
      "content-length": String(bytes.byteLength),
      etag,
      "cache-control": target.version
        ? "public, max-age=31536000, immutable"
        : "public, max-age=300",
      "x-resq-version": version,
      "x-resq-commit": release.commit,
      "x-resq-sha256": expected,
      "x-resq-source": `github:${REPO}@${release.commit}/${meta.path}`,
    },
  });
}
