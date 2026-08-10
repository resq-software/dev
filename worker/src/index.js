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

const PINS = {
  latest: "0.3.0",
  releases: {
    "0.3.0": {
      commit: "afbc33517c51d5e2555d99f25374b42d3176177f",
      artifacts: {
        "install.sh": "4ccc02b035d825b930a0612e07a9d4bca19d32ab891e711f6c3f445a29ebc826",
        "install.ps1": "d7e7e43b99183346e2c9a6a3269856455a7e3ed19b4d63bab79eb2d12c87dace",
        "scripts/install-hooks.sh": "24bd874dd27ff55153be602a5ad7fb366f4283ae4423323f8fd2bc2af442c68a",
        "scripts/install-hooks.ps1": "4976c3920f5e2c5e6d347ed791d00119f46152c946a6f8186a98690deef9dd23",
        "scripts/install-resq.sh": "38a70c003b3b83f8cf5e78961fea1246b69247a800fc1788167e5b4ea44759bf",
        "scripts/setup.sh": "6792ee2e02bcfa982046a36ed68532f4af44be93fd1243fc77a253d303767ca1",
        "scripts/setup.ps1": "899a4840661be11ab3104e1aca60f3bfb78f8a7139bf6a373803d6c1c0a8db55",
      },
    },
  },
};

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
const ARTIFACTS = {
  "install.sh": { path: "install.sh", type: SHELL, shell: true },
  "install.ps1": { path: "install.ps1", type: PWSH, shell: false },
  "hooks.sh": { path: "scripts/install-hooks.sh", type: SHELL, shell: true },
  "hooks.ps1": { path: "scripts/install-hooks.ps1", type: PWSH, shell: false },
  "resq.sh": { path: "scripts/install-resq.sh", type: SHELL, shell: true },
  "setup.sh": { path: "scripts/setup.sh", type: SHELL, shell: true },
  "setup.ps1": { path: "scripts/setup.ps1", type: PWSH, shell: false },
};

// Accept the repo basename too, so a URL copied out of the repo still works.
const ALIASES = {
  "install-hooks.sh": "hooks.sh",
  "install-resq.sh": "resq.sh",
};

// ── Helpers ─────────────────────────────────────────────────────────────────

function pins(env) {
  if (!env || typeof env.RESQ_PINS !== "string") return PINS;
  try {
    const parsed = JSON.parse(env.RESQ_PINS);
    // Validate the shape before trusting it. A half-formed override that
    // slipped through a bad deploy must not disable verification.
    const rel = parsed?.releases?.[parsed?.latest];
    if (!rel || !/^[0-9a-f]{40}$/.test(rel.commit ?? "")) return PINS;
    if (!rel.artifacts || typeof rel.artifacts !== "object") return PINS;
    return parsed;
  } catch {
    return PINS;
  }
}

function hex(buffer) {
  const bytes = new Uint8Array(buffer);
  let out = "";
  for (let i = 0; i < bytes.length; i++) out += bytes[i].toString(16).padStart(2, "0");
  return out;
}

async function sha256Hex(bytes) {
  return hex(await crypto.subtle.digest("SHA-256", bytes));
}

// Length-independent comparison. These digests are public so timing is not a
// real oracle, but comparing this way costs nothing and keeps the habit.
function digestsEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Read a body with a hard ceiling, enforced as chunks arrive. Returns null if
// the cap is exceeded so the caller can fail closed.
async function readCapped(response, max) {
  const declared = response.headers.get("content-length");
  if (declared !== null && Number(declared) > max) return null;
  if (!response.body) return null;

  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
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
function errorBody(message, asShell) {
  if (!asShell) return `resq: ${message}\n`;
  return `#!/bin/sh\n# resq installer: ${message}\nprintf '%s\\n' 'resq installer: ${message}' >&2\nexit 1\n`;
}

function baseHeaders() {
  return {
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; sandbox",
    "referrer-policy": "no-referrer",
    "cross-origin-resource-policy": "same-origin",
    "x-frame-options": "DENY",
    "strict-transport-security": "max-age=63072000; includeSubDomains; preload",
  };
}

function errorResponse(status, message, asShell) {
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
function route(pathname) {
  const parts = pathname.split("/").filter(Boolean);

  if (parts.length === 0) return { version: null, name: "install.sh" };
  if (parts.length > 2) return null;

  let version = null;
  let name = parts[0];
  if (parts.length === 2) {
    version = parts[0].replace(/^v/, "");
    name = parts[1];
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
async function verifiedFetch(commit, repoPath, expectedDigest, ctx) {
  const cache = caches.default;
  const cacheKey = new Request(`https://pin.resq.internal/${commit}/${repoPath}`);

  const cached = await cache.match(cacheKey);
  if (cached) {
    const bytes = new Uint8Array(await cached.arrayBuffer());
    // Re-verify on the way out of cache. Cheap, and it means a poisoned or
    // truncated cache entry can never be served.
    if (digestsEqual(await sha256Hex(bytes), expectedDigest)) return bytes;
  }

  const upstream = await fetch(
    `https://raw.githubusercontent.com/${REPO}/${commit}/${repoPath}`,
    {
      cf: { cacheTtl: 3600, cacheEverything: true },
      headers: { "user-agent": "get.resq.software" },
      redirect: "error",
    },
  );
  if (!upstream.ok) return null;

  const bytes = await readCapped(upstream, MAX_BYTES);
  if (bytes === null) return null;

  if (!digestsEqual(await sha256Hex(bytes), expectedDigest)) return null;

  ctx.waitUntil(
    cache.put(
      cacheKey,
      new Response(bytes, { headers: { "cache-control": "public, max-age=86400" } }),
    ),
  );
  return bytes;
}

// ── Generated documents ─────────────────────────────────────────────────────

function sha256sums(release) {
  return (
    Object.entries(release.artifacts)
      .sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([path, digest]) => `${digest}  ${path}`)
      .join("\n") + "\n"
  );
}

function manifest(config, version, release) {
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
  async fetch(request, env, ctx) {
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
      : null;
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

    return new Response(request.method === "HEAD" ? null : bytes, {
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
  },
};
