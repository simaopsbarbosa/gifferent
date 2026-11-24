import { draftKey, isLoopback, publishedKey, reportAt } from "./report.js";
import { githubLogin, repositories } from "./github.js";
import { sessions, sessionName, sha256 } from "./session.js";

export { Report } from "./report.js";
export { GitHubSession } from "./session.js";
export { BugReportWorkflow } from "./workflow.js";

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const maxGIF = 9_000_000;
const maxMetadata = 6_000;
const reportID = "[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}";
const securityHeaders = {
  "cache-control": "no-store",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  "x-content-type-options": "nosniff",
};

class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function respond(body, contentType, options = {}) {
  return new Response(body, {
    status: options.status ?? 200,
    headers: { ...securityHeaders, "content-type": contentType, ...options.headers },
  });
}

const json = (body, status = 200) => respond(JSON.stringify(body), "application/json", { status });
const missing = () => json({ error: "report unavailable" }, 404);

async function readBody(request, maxBytes) {
  if (Number(request.headers.get("content-length")) > maxBytes) {
    throw new RequestError(413, "request exceeds the size limit");
  }
  if (!request.body) throw new RequestError(400, "missing request body");
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel();
        throw new RequestError(413, "request exceeds the size limit");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function connection(request, env) {
  const key = request.headers.get("authorization")?.match(/^Bearer ([a-f0-9]{64})$/i)?.[1];
  if (!key) throw new RequestError(401, "connect GitHub to continue");
  const name = await sessionName(key);
  return { name, store: sessions(env, name) };
}

async function startConnection(request, env) {
  if (!env.GITHUB_CLIENT_ID || !env.GITHUB_APP_SLUG) {
    throw new RequestError(503, "GitHub sign-in has not been configured");
  }
  const { success } = await env.CONNECT_LIMIT.limit({ key: request.headers.get("cf-connecting-ip") ?? "local" });
  if (!success) throw new RequestError(429, "wait before starting another GitHub sign-in");
  const code = await githubLogin(env, "/login/device/code");
  if (!code.user_code || !code.device_code || !code.interval || !code.expires_in) {
    throw new RequestError(503, "could not start GitHub sign-in");
  }
  const key = crypto.getRandomValues(new Uint8Array(32)).toHex();
  await sessions(env, await sessionName(key)).start(code);
  return json({ key, code: code.user_code, interval: code.interval, expiresIn: code.expires_in });
}

function metadata(request) {
  const encoded = request.headers.get("x-gifferent-report");
  let body;
  try {
    if (!encoded || encoded.length > maxMetadata * 4 / 3) throw new Error();
    body = JSON.parse(decoder.decode(Uint8Array.fromBase64(encoded)));
  } catch {
    throw new RequestError(400, "invalid report fields");
  }
  const fields = { repository: 150, title: 120, steps: 1_000, expected: 1_000, actual: 1_000 };
  const result = {};
  for (const [key, max] of Object.entries(fields)) {
    const value = typeof body?.[key] === "string"
      ? body[key].replace(/\r\n?/g, "\n").trim() : "";
    if (!value || [...value].length > max) throw new RequestError(400, `invalid ${key}`);
    result[key] = value;
  }
  if (/[\n\u0000-\u001f\u007f]/.test(result.title)
      || !/^[a-z0-9-]+\/[a-z0-9_.-]+$/i.test(result.repository)
      || !Number.isSafeInteger(body.repositoryID) || body.repositoryID < 1) {
    throw new RequestError(400, "use a single-line title and choose a GitHub repository");
  }
  return { ...result, repositoryID: body.repositoryID };
}

async function upload(request, env, id, account, profile) {
  if (request.headers.get("content-type") !== "image/gif") {
    throw new RequestError(415, "the upload must be a GIF");
  }
  const input = metadata(request);
  const store = reportAt(env, id);
  const existing = await store.read();
  if (existing && existing.owner !== profile.id) return missing();
  // retries of an accepted report still work after its repository access changes.
  if (!existing || existing.state === "uploading") {
    const token = await account.store.access();
    if (!token) throw new RequestError(401, "reconnect GitHub to publish");
    const available = await repositories(env, token);
    if (!available.some((repo) => repo.id === input.repositoryID)) {
      throw new RequestError(403, "grant access to a public repository with issues enabled");
    }
  }
  const bytes = await readBody(request, maxGIF);
  const signature = String.fromCharCode(...bytes.subarray(0, 6));
  if (bytes.length < 14 || !["GIF87a", "GIF89a"].includes(signature) || bytes.at(-1) !== 0x3b) {
    throw new RequestError(400, "invalid GIF file");
  }
  const fingerprint = await sha256(encoder.encode(JSON.stringify(input) + await sha256(bytes)));
  let state = await store.reserve(id, input, fingerprint, profile.id, account.name);
  if (state === "missing") return missing();
  if (state === "conflict") throw new RequestError(409, "this submission ID has different contents");
  if (state === "uploading") {
    await env.CLIPS.put(draftKey(id), bytes, {
      onlyIf: { etagDoesNotMatch: "*" }, customMetadata: { digest: fingerprint },
    });
    state = await store.uploaded(account.name);
    if (state === "expired") await env.CLIPS.delete(draftKey(id));
  }
  if (state === "expired") throw new RequestError(410, "the upload expired");
  return json({ state }, 202);
}

async function gif(env, key) {
  const object = await env.CLIPS.get(key);
  if (!object) return missing();
  return respond(object.body, "image/gif", {
    headers: { "content-length": String(object.size) },
  });
}

async function api(request, env, path) {
  const { method } = request;
  if (path === "/api/connect" && method === "POST") return startConnection(request, env);
  const account = await connection(request, env);
  if (path === "/api/connect" && method === "GET") {
    const result = await account.store.complete();
    return json(result, result.error ? 401 : 200);
  }
  if (path === "/api/connect" && method === "DELETE") {
    await account.store.disconnect();
    return json({});
  }
  const profile = await account.store.profile();
  if (!profile) throw new RequestError(401, "reconnect GitHub to continue");
  if (path === "/api/repositories" && method === "GET") {
    const token = await account.store.access();
    if (!token) throw new RequestError(401, "reconnect GitHub to continue");
    if (!/^[a-z0-9-]+$/.test(env.GITHUB_APP_SLUG ?? "")) {
      throw new RequestError(503, "GitHub sign-in has not been configured");
    }
    return json({
      profile, repositories: await repositories(env, token),
      grantURL: `https://github.com/apps/${env.GITHUB_APP_SLUG}/installations/new`,
    });
  }
  const route = path.match(new RegExp(`^/api/reports/(${reportID})$`));
  if (!route) return missing();
  const [, id] = route;
  if (method === "PUT") return upload(request, env, id, account, profile);
  if (method !== "GET") return missing();
  const report = await reportAt(env, id).read();
  if (!report || report.owner !== profile.id) return missing();
  const { state, issueUrl, needsReconciliation, reconnect } = report;
  return json({ state, issueUrl, needsReconciliation, reconnect });
}

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      if (url.origin !== env.PUBLIC_ORIGIN || (url.protocol !== "https:" && !isLoopback(url.origin))) {
        return missing();
      }
      if (url.pathname.startsWith("/api/")) return await api(request, env, url.pathname);
      const clip = url.pathname.match(new RegExp(`^/clips/(${reportID})/(${reportID})[.]gif$`));
      if (request.method === "GET" && clip) {
        const [, id, key] = clip;
        const report = await reportAt(env, id).read();
        if (report?.state === "published" && report.clipKey === key) return await gif(env, publishedKey(id));
      }
      return missing();
    } catch (error) {
      if (error instanceof RequestError) return json({ error: error.message }, error.status);
      if (error.status === 401) return json({ error: "reconnect GitHub to continue" }, 401);
      return json({ error: "report service unavailable; retry the request" }, 503);
    }
  },
};
