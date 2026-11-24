import { NonRetryableError } from "cloudflare:workflows";
import { isLoopback } from "./report.js";

function literal(text) {
  // a block quote with escaped punctuation preserves user text without mentions or embedded links.
  return text.split("\n").map((line) => "> " + line.replace(
    /[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]/g, "\\$&",
  )).join("\n");
}

export function issueBody(report, origin) {
  const { id, input, clipKey } = report;
  return [
    "## Steps to reproduce", literal(input.steps),
    "## Expected behavior", literal(input.expected),
    "## Actual behavior", literal(input.actual),
    `[View GIF recording](${origin}/clips/${id}/${clipKey}.gif)`,
    marker(id),
  ].join("\n\n");
}

const marker = (id) => `<!-- gifferent-report:${id} -->`;

function mockOrigin(env) {
  if (!isLoopback(env.PUBLIC_ORIGIN)) return null;
  if (!env.LOCAL_GITHUB_ORIGIN || !isLoopback(env.LOCAL_GITHUB_ORIGIN)) {
    throw new NonRetryableError("local reports require the loopback GitHub fixture");
  }
  return env.LOCAL_GITHUB_ORIGIN;
}

export function github(env, token, path, options = {}) {
  return fetch((mockOrigin(env) ?? "https://api.github.com") + path, {
    ...options, redirect: "manual", signal: AbortSignal.timeout(12_000),
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      "user-agent": "gifferent-bug-reports",
      "x-github-api-version": "2022-11-28",
    },
  });
}

export async function githubLogin(env, path, params = {}) {
  const response = await fetch((mockOrigin(env) ?? "https://github.com") + path, {
    method: "POST", redirect: "manual", signal: AbortSignal.timeout(12_000),
    headers: { accept: "application/json" },
    body: new URLSearchParams({ client_id: env.GITHUB_CLIENT_ID, ...params }),
  });
  if (!response.ok) throw new Error("GitHub sign-in unavailable");
  return response.json();
}

async function paginate(env, token, path, key) {
  const rows = [];
  for (let page = 1; ; page++) {
    const response = await github(env, token, `${path}?per_page=100&page=${page}`);
    if (response.status === 401) {
      throw Object.assign(new Error("reconnect GitHub to publish"), { status: 401 });
    }
    if (!response.ok) readFailure(response);
    const data = await response.json();
    rows.push(...data[key]);
    if (!response.headers.get("link")?.includes('rel="next"')) return rows;
  }
}

export const usableRepo = (repo) => repo.visibility === "public" && repo.has_issues
  && !repo.archived && !repo.disabled;

export async function repositories(env, token) {
  const installations = await paginate(env, token, "/user/installations", "installations");
  const available = new Map();
  for (const { id } of installations) {
    const repos = await paginate(env, token, `/user/installations/${id}/repositories`, "repositories");
    for (const repo of repos) {
      if (usableRepo(repo)) available.set(repo.id, { id: repo.id, name: repo.full_name });
    }
  }
  return [...available.values()].sort((a, b) => a.name.localeCompare(b.name));
}

function throttled(response) {
  return response.status === 429 || (response.status === 403
    && (response.headers.get("x-ratelimit-remaining") === "0" || response.headers.has("retry-after")));
}

function retryAt(response) {
  const after = response.headers.get("retry-after");
  if (after && /^\d+$/.test(after)) return Date.now() + Number(after) * 1_000;
  const reset = Number(response.headers.get("x-ratelimit-reset"));
  if (response.headers.get("x-ratelimit-remaining") === "0" && reset > 0) return reset * 1_000;
  return Date.now() + 60_000;
}

function readFailure(response) {
  if (throttled(response) || response.status >= 500) throw new Error(`GitHub HTTP ${response.status}`);
  if (response.status === 401) throw new NonRetryableError("reconnect GitHub to publish");
  throw new NonRetryableError(`GitHub HTTP ${response.status}`);
}

function issueUrl(env, repository, issue) {
  if (!Number.isSafeInteger(issue.number) || issue.number < 1) {
    throw new Error("GitHub issue response is missing an issue number");
  }
  return `${mockOrigin(env) ?? "https://github.com"}/${repository}/issues/${issue.number}`;
}

async function reconcile(env, github, endpoint, report) {
  // list recent issues directly, including closed ones, without depending on search indexing.
  const since = new Date(report.createdAt - 60_000).toISOString();
  for (let page = 1; page <= 10; page++) {
    const response = await github(
      `${endpoint}/issues?state=all&since=${since}&per_page=100&page=${page}`,
    );
    if (!response.ok) readFailure(response);
    const issues = await response.json();
    const match = issues.find(
      (issue) => !issue.pull_request && issue.body?.endsWith(marker(report.id)),
    );
    if (match) return issueUrl(env, report.input.repository, match);
    if (issues.length < 100) break;
  }
  throw new Error("GitHub create outcome is unknown; waiting to reconcile");
}

export async function publishIssue(env, token, store, report) {
  if (report.issueUrl) return report.issueUrl;
  if (report.nextGitHubAt > Date.now()) throw new Error("waiting for GitHub rate limit");
  const request = (path, options) => github(env, token, path, options);
  const selected = (await repositories(env, token)).find((repo) => repo.id === report.input.repositoryID);
  if (!selected || !/^[a-z0-9-]+\/[a-z0-9_.-]+$/i.test(selected.name)) {
    throw new NonRetryableError("grant access to a public repository with issues enabled");
  }
  const repository = selected.name;
  const endpoint = `/repos/${repository}`;
  const metadata = await request(endpoint);
  if (!metadata.ok) readFailure(metadata);
  const repo = await metadata.json();
  if (repo.id !== selected.id || !usableRepo(repo)) {
    throw new NonRetryableError("the repository must be public and have issues enabled");
  }
  if (report.createState === "posting") {
    return reconcile(env, request, endpoint, { ...report, input: { ...report.input, repository } });
  }

  if (!await store.claimCreate()) throw new Error("GitHub create already in progress");
  const response = await request(`${endpoint}/issues`, {
    method: "POST",
    body: JSON.stringify({ title: report.input.title, body: issueBody(report, env.PUBLIC_ORIGIN) }),
  });
  if (response.status === 201) return issueUrl(env, repository, await response.json());
  if (throttled(response)) {
    await store.markCreate("none", { nextGitHubAt: retryAt(response) });
    throw new Error(`GitHub rate limited the create request (${response.status})`);
  }
  if (response.status >= 500 || response.status < 400 || response.status === 408) {
    throw new Error("GitHub create outcome is unknown");
  }
  await store.markCreate("none");
  readFailure(response);
}
