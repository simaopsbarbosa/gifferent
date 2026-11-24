import { createServer } from "node:http";
import { pathToFileURL } from "node:url";

export const repository = { id: 42, full_name: "gifferent-test/bugs", visibility: "public", has_issues: true };

export function createMockGitHub(reportError = console.error) {
  const issues = [];
  const posts = new Map();
  let signIns = 0;
  let refreshes = 0;
  let hidden = false;
  const endpoint = "/repos/" + repository.full_name;

  async function handle(request, response) {
    const url = new URL(request.url, "http://localhost");
    const answer = (status, data) => response.writeHead(status, { "content-type": "application/json" })
      .end(JSON.stringify(data));
    if (url.pathname === "/login/device/code" && request.method === "POST") {
      signIns++;
      return answer(200, { device_code: String(signIns), user_code: "TEST-CODE", interval: 1, expires_in: 20 });
    }
    if (url.pathname === "/login/oauth/access_token" && request.method === "POST") {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = new URLSearchParams(Buffer.concat(chunks).toString("utf8"));
      const refresh = body.get("refresh_token");
      if (refresh) refreshes++;
      const id = refresh?.split("_").at(-1) ?? body.get("device_code");
      return answer(200, { access_token: `ghu_fixture_${id}`, refresh_token: `ghr_fixture_${id}`,
        expires_in: refresh ? 28_800 : 30 });
    }

    const match = request.headers.authorization?.match(/^Bearer ghu_fixture_(\d+)$/);
    if (!match) return answer(401, {});
    const id = Number(match[1]);
    if (url.pathname === "/user") return answer(200, { id, login: `tester-${id}` });
    if (url.pathname === "/user/installations") return answer(200, { installations: [{ id: 1 }] });
    if (url.pathname === "/user/installations/1/repositories") {
      return answer(200, { repositories: [
        { ...repository, visibility: hidden ? "private" : "public" },
        { ...repository, id: 43, full_name: "gifferent-test/private", visibility: "private" },
      ] });
    }
    if (url.pathname === endpoint) {
      return answer(200, { ...repository, visibility: hidden ? "private" : "public" });
    }
    if (url.pathname !== endpoint + "/issues") return answer(404, {});
    if (request.method === "GET") return answer(200, issues);
    if (request.method !== "POST") return answer(405, {});

    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const { title, body } = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    const count = (posts.get(title) ?? 0) + 1;
    posts.set(title, count);
    if (title === "rate limited" && count === 1) {
      response.setHeader("retry-after", "1");
      return answer(429, { message: "try again" });
    }
    if (title === "rejected") return answer(422, {});
    const issue = { number: issues.length + 1, title, body };
    issues.push(issue);
    if (title === "lost response") return request.socket.destroy();
    return answer(201, issue);
  }

  const server = createServer((request, response) => {
    void handle(request, response).catch((error) => {
      reportError(error);
      response.writeHead(500).end();
    });
  });
  return {
    server, issues, posts,
    hide: (value) => { hidden = value; },
    refreshes: () => refreshes,
  };
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  createMockGitHub().server.listen(8788, "127.0.0.1");
}
