import { DurableObject } from "cloudflare:workers";

export const draftKey = (id) => `draft/${id}`;
export const publishedKey = (id) => `published/${id}`;
export const reportAt = (env, id) => env.REPORTS.getByName(id);
export const isLoopback = (origin) => {
  const url = new URL(origin);
  return url.protocol === "http:" && url.hostname === "127.0.0.1";
};

export class Report extends DurableObject {
  read() {
    return this.ctx.storage.kv.get("report");
  }

  async save(report, alarmAt) {
    this.ctx.storage.kv.put("report", report);
    if (alarmAt !== undefined) await this.ctx.storage.setAlarm(alarmAt);
  }

  async reserve(id, input, digest, owner, connection) {
    const existing = this.read();
    if (existing) {
      if (existing.owner !== owner) return "missing";
      return existing.digest === digest ? existing.state : "conflict";
    }
    const createdAt = Date.now();
    const expiresAt = createdAt + 15 * 60_000;
    await this.save({
      id, input, digest, owner, connection, createdAt, expiresAt, state: "uploading", attempt: 0,
      clipKey: crypto.randomUUID(), createState: "none",
    }, expiresAt);
    return "uploading";
  }

  async uploaded(connection) {
    const report = this.read();
    if (report.state !== "uploading") return report.state;
    if (Date.now() >= report.expiresAt) return "expired";
    await this.save({ ...report, connection, state: "publishing" }, Date.now());
    return "publishing";
  }

  async nextAttempt() {
    const report = this.read();
    if (report.state !== "publishing") return report;
    const next = { ...report, attempt: report.attempt + 1 };
    await this.save(next);
    return next;
  }

  async claimCreate() {
    const report = this.read();
    if (report.state !== "publishing" || report.createState !== "none") return false;
    await this.save({ ...report, createState: "posting" });
    return true;
  }

  async markCreate(createState, { issueUrl, nextGitHubAt } = {}) {
    const report = this.read();
    if (report.state !== "publishing") return;
    await this.save({ ...report, createState, issueUrl, nextGitHubAt });
  }

  async published() {
    const report = this.read();
    if (report.state === "publishing" && report.issueUrl) {
      await this.save({ ...report, input: null, connection: null, state: "published" });
    }
  }

  async fail(reconnect) {
    const report = this.read();
    if (report.state !== "publishing") return;
    const needsReconciliation = report.createState !== "none";
    await this.save({
      ...report, input: null, connection: null, state: "failed", needsReconciliation,
      reconnect: reconnect && !needsReconciliation,
    });
  }

  async alarm() {
    const report = this.read();
    const { id, state, expiresAt } = report;
    if (state === "uploading" || state === "expired") {
      if (state !== "expired") await this.save({ ...report, input: null, connection: null, state: "expired" });
      await this.env.CLIPS.delete(draftKey(id));
    } else if (state === "publishing") {
      try {
        await this.env.BUG_REPORT.create({ id, params: { id } });
      } catch (error) {
        const instance = await this.env.BUG_REPORT.get(id);
        if ((await instance.status()).status === "unknown") {
          if (Date.now() >= expiresAt) {
            await this.fail(false);
            await this.env.CLIPS.delete(draftKey(id));
          } else {
            await this.ctx.storage.setAlarm(Math.min(expiresAt, Date.now() + 15_000));
          }
        }
      }
    }
  }
}
