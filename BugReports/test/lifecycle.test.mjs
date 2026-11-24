import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { readFile, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { createMockGitHub, repository } from "./mock-github.mjs";

const directory = fileURLToPath(new URL("../", import.meta.url));
const bytes = await readFile(new URL(
  "../../Benchmarks/reviews/gifski-quality-sweep-2026-10-24/gifs/mostly-static-ui-quality-90.gif",
  import.meta.url,
));
const clipPattern = /\[View GIF recording\]\(([^)]+)\)/;
const fields = {
  repository: repository.full_name, repositoryID: repository.id, title: "rate limited",
  steps: "1. pick a slot\n2. switch weeks <script>bad</script>", expected: "slot stays selected",
  actual: "selection disappears",
};

const { server, issues, posts, hide, refreshes } = createMockGitHub((error) => {
  workerLog += error.stack;
});
let worker;
let scratch;
let origin;
let github;
let workerLog = "";

async function bind(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return `http://127.0.0.1:${server.address().port}`;
}

async function until(fn, timeout = 20_000) {
  const end = Date.now() + timeout;
  let error;
  do {
    try {
      const result = await fn();
      if (result) return result;
    } catch (cause) {
      error = cause;
    }
    await delay(100);
  } while (Date.now() < end);
  const relevantLogs = workerLog.split("\n").filter((line) => !line.includes("/status 200"));
  throw new Error(`timed out: ${error ?? ""}\n${relevantLogs.slice(-36).join("\n")}`);
}

before(async () => {
  github = await bind(server);
  const portProbe = createServer();
  origin = await bind(portProbe);
  await new Promise((resolve) => portProbe.close(resolve));
  scratch = await mkdtemp(join(tmpdir(), "gifferent-report-test-"));
  await writeFile(join(scratch, "test.vars"), [
    "GITHUB_CLIENT_ID=fixture-client", "GITHUB_APP_SLUG=gifferent-fixture",
    `PUBLIC_ORIGIN=${origin}`, `LOCAL_GITHUB_ORIGIN=${github}`,
  ].join("\n"));
  worker = spawn(process.execPath, [
    "node_modules/wrangler/bin/wrangler.js", "dev", "--ip", "127.0.0.1", "--port",
    new URL(origin).port, "--persist-to", scratch, "--env-file", join(scratch, "test.vars"),
    "--show-interactive-dev-session=false",
  ], { cwd: directory, env: { ...process.env, WRANGLER_SEND_METRICS: "false",
    WRANGLER_LOG_PATH: join(scratch, "wrangler.log") }, stdio: ["ignore", "pipe", "pipe"] });
  for (const stream of [worker.stdout, worker.stderr]) stream.on("data", (chunk) => { workerLog += chunk; });
  await until(async () => (await fetch(origin + "/")).status === 404, 35_000);
});

after(async () => {
  if (worker && worker.exitCode === null) {
    worker.kill();
    await once(worker, "exit");
  }
  server?.closeAllConnections();
  server?.close();
  if (scratch) await rm(scratch, { recursive: true, force: true });
});

const bearer = (key) => ({ authorization: `Bearer ${key}` });
const reportURL = (id) => `${origin}/api/reports/${id}`;

async function connect() {
  const url = origin + "/api/connect";
  const started = await fetch(url, { method: "POST" });
  assert.equal(started.status, 200, await started.clone().text());
  const { key, code } = await started.json();
  assert.equal(code, "TEST-CODE");
  assert.match(key, /^[a-f0-9]{64}$/);
  const profile = await until(async () => {
    const response = await fetch(url, { headers: bearer(key) });
    return (await response.json()).profile;
  });
  return { key, profile };
}

function upload(id, key, input = fields, clip = bytes) {
  return fetch(reportURL(id), {
    method: "PUT",
    headers: { ...bearer(key), "content-type": "image/gif",
      "x-gifferent-report": Buffer.from(JSON.stringify(input)).toString("base64") },
    body: clip,
  });
}

async function state(id, key, expected) {
  return until(async () => {
    const response = await fetch(reportURL(id), { headers: bearer(key) });
    const current = await response.json();
    assert.equal(current.state, expected);
    return current;
  });
}

async function assertClipRemoved(url) {
  // local R2 emulation exposes its SQLite index under the temporary persistence directory.
  // the Workflow's successful cleanup step is below the endpoint-level access checks.
  const { DatabaseSync } = await import("node:sqlite");
  const { glob } = await import("node:fs/promises");
  const id = url.split("/").at(-1);
  await until(async () => {
    const dbs = await Array.fromAsync(glob("**/*.sqlite", { cwd: scratch }));
    const dbPath = dbs.find((file) => file.includes("r2"));
    assert.ok(dbPath, "local R2 persistence index");
    const database = new DatabaseSync(join(scratch, dbPath), { readOnly: true });
    try {
      const count = database.prepare("SELECT count(*) AS total FROM _mf_objects WHERE key = ?")
        .get("draft/" + id).total;
      assert.equal(count, 0, "draft object should have been deleted");
      return true;
    } finally {
      database.close();
    }
  });
}


test("connect, list permitted repositories, and publish once after a rate limit", { timeout: 35_000 }, async () => {
  const { key, profile } = await connect();
  const { key: otherKey } = await connect();
  const connections = await Promise.all([1, 2].map(() =>
    fetch(origin + "/api/repositories", { headers: bearer(key) })));
  for (const response of connections) {
    assert.deepEqual(await response.json(), {
      profile, repositories: [{ id: repository.id, name: repository.full_name }],
      grantURL: "https://github.com/apps/gifferent-fixture/installations/new",
    });
  }
  assert.equal(refreshes(), 1, "concurrent requests share one token refresh");

  const id = crypto.randomUUID();
  assert.equal((await upload(id, "wrong")).status, 401);
  assert.equal((await upload(id, key, fields, Buffer.from("bad"))).status, 400);
  assert.equal((await upload(id, key, fields, Buffer.alloc(9_000_001))).status, 413);
  assert.equal((await upload(id, key, { ...fields, repositoryID: 43 })).status, 403);
  const duplicates = await Promise.all([upload(id, key), upload(id, key)]);
  for (const response of duplicates) assert.equal(response.status, 202, await response.clone().text());
  assert.equal((await upload(id, key, { ...fields, title: "changed" })).status, 409);
  assert.equal((await fetch(reportURL(id))).status, 401);
  assert.equal((await fetch(reportURL(id), { headers: bearer(otherKey) })).status, 404);
  assert.equal((await upload(id, otherKey)).status, 404);
  assert.equal((await fetch(`${origin}/reports/${id}`)).status, 404, "no browser review page");
  await state(id, key, "publishing");
  const result = await state(id, key, "published");
  assert.equal(result.issueUrl, `${github}/${repository.full_name}/issues/1`);
  assert.equal(issues.length, 1);
  assert.equal(posts.get(fields.title), 2);
  const clip = await fetch(issues[0].body.match(clipPattern)[1]);
  assert.ok(clip.ok);
  assert.deepEqual(Buffer.from(await clip.arrayBuffer()), bytes);
  await assertClipRemoved(reportURL(id));
});

test("recover a lost GitHub reply without another create", { timeout: 25_000 }, async () => {
  const { key } = await connect();
  const id = crypto.randomUUID();
  assert.equal((await upload(id, key, { ...fields, title: "lost response" })).status, 202);
  assert.match((await state(id, key, "published")).issueUrl, /issues\/2$/);
  assert.equal(posts.get("lost response"), 1);
});

test("a rejected publish cleans up and private repositories cannot receive uploads", { timeout: 25_000 }, async () => {
  const { key } = await connect();
  const id = crypto.randomUUID();
  hide(true);
  try {
    assert.equal((await upload(id, key)).status, 403);
  } finally {
    hide(false);
  }
  assert.equal((await upload(id, key, { ...fields, title: "rejected" })).status, 202);
  const result = await state(id, key, "failed");
  assert.equal(result.needsReconciliation, false);
  await assertClipRemoved(reportURL(id));
  assert.equal((await fetch(origin + "/api/connect", { method: "DELETE", headers: bearer(key) })).status, 200);
  assert.equal((await fetch(reportURL(id), { headers: bearer(key) })).status, 401);
});
