import { DurableObject } from "cloudflare:workers";
import { github, githubLogin } from "./github.js";

const minutes = 60_000;
const sessionLifetime = 30 * 24 * 60 * minutes;
export const sessions = (env, name) => env.SESSIONS.getByName(name);
export const sha256 = async (bytes) => new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();
export const sessionName = (key) => sha256(new TextEncoder().encode(key));

export class GitHubSession extends DurableObject {
  #operation;

  async #once(action) {
    if (this.#operation) return this.#operation;
    this.#operation = action().finally(() => { this.#operation = undefined; });
    return this.#operation;
  }

  async start(code) {
    const expires = Date.now() + code.expires_in * 1000;
    this.ctx.storage.kv.put("login", {
      device: code.device_code, next: Date.now() + code.interval * 1000,
      interval: code.interval, expires,
    });
    await this.ctx.storage.setAlarm(expires);
  }

  profile() {
    const account = this.ctx.storage.kv.get("account");
    if (account?.expires > Date.now()) return account.profile;
  }

  async complete() {
    const active = this.profile();
    if (active) return { profile: active };
    return this.#once(async () => {
      const login = this.ctx.storage.kv.get("login");
      if (!login || login.expires <= Date.now()) return { error: "GitHub sign-in expired" };
      if (login.next > Date.now()) return { interval: Math.ceil((login.next - Date.now()) / 1000) };
      login.next = Date.now() + login.interval * 1000;
      this.ctx.storage.kv.put("login", login);

      let token = login.token;
      if (!token) {
        token = await githubLogin(this.env, "/login/oauth/access_token", {
          device_code: login.device, grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        });
        if (!this.ctx.storage.kv.get("login")) return { error: "GitHub sign-in expired" };
        if (token.error === "slow_down" || token.error === "authorization_pending") {
          login.interval = Math.max(login.interval, token.interval ?? login.interval)
            + (token.error === "slow_down" && !token.interval ? 5 : 0);
          login.next = Date.now() + login.interval * 1000;
          this.ctx.storage.kv.put("login", login);
          return { interval: login.interval };
        }
        if (!token.access_token?.startsWith("ghu_")) {
          return { error: "GitHub sign-in was denied or expired" };
        }
        if (!token.refresh_token || !Number.isFinite(token.expires_in)) {
          throw new Error("configure the GitHub App to issue expiring user tokens");
        }
        // keep the exchanged token if reading the profile needs a retry.
        this.ctx.storage.kv.put("login", { ...login, device: undefined, token });
      }
      const response = await github(this.env, token.access_token, "/user");
      if (!response.ok) throw new Error("could not read GitHub account");
      const { id, login: username } = await response.json();
      if (!Number.isSafeInteger(id) || !username) throw new Error("invalid GitHub account");
      const profile = { id, username };
      if (!this.ctx.storage.kv.get("login")) return { error: "GitHub sign-in expired" };
      const expires = Date.now() + sessionLifetime;
      this.#saveToken(token, profile, expires);
      this.ctx.storage.kv.delete("login");
      await this.ctx.storage.setAlarm(expires);
      return { profile };
    });
  }

  #saveToken(token, profile, expires) {
    this.ctx.storage.kv.put("account", {
      profile, expires, token: token.access_token, refresh: token.refresh_token,
      tokenExpires: Date.now() + token.expires_in * 1000,
    });
  }

  async access() {
    const account = this.ctx.storage.kv.get("account");
    if (!account || account.expires <= Date.now()) return null;
    if (account.tokenExpires > Date.now() + minutes) return account.token;
    if (!account.refresh) return null;
    return this.#once(async () => {
      const token = await githubLogin(this.env, "/login/oauth/access_token", {
        grant_type: "refresh_token", refresh_token: account.refresh,
      });
      if (!this.profile() || !token.access_token) return null;
      this.#saveToken(token, account.profile, account.expires);
      return token.access_token;
    });
  }

  async disconnect() {
    await this.ctx.storage.deleteAll();
  }

  async alarm() {
    await this.disconnect();
  }
}
