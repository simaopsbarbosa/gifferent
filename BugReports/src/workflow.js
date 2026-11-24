import { WorkflowEntrypoint } from "cloudflare:workers";
import { NonRetryableError } from "cloudflare:workflows";
import { publishIssue } from "./github.js";
import { draftKey, publishedKey, reportAt } from "./report.js";

import { sessions } from "./session.js";

const reconnectMessage = "reconnect GitHub to publish";

export class BugReportWorkflow extends WorkflowEntrypoint {
  async run(event, step) {
    const { id } = event.payload;
    const store = reportAt(this.env, id);
    const clips = this.env.CLIPS;
    try {
      await step.do("retain approved clip", async () => {
        if (await clips.head(publishedKey(id))) return;
        const report = await store.read();
        const clip = await clips.get(draftKey(id));
        if (!clip || clip.customMetadata?.digest !== report.digest) throw new NonRetryableError("approved clip is missing");
        await clips.put(publishedKey(id), await clip.arrayBuffer());
      });

      await step.do("publish issue to GitHub", {
        retries: { limit: 5, delay: "10 seconds", backoff: "exponential" },
        timeout: "4 minutes",
      }, async () => {
        const report = await store.nextAttempt();
        if (report.state === "published") return;
        const token = await sessions(this.env, report.connection).access();
        if (!token) throw new NonRetryableError(reconnectMessage);
        let issueUrl;
        try {
          issueUrl = await publishIssue(this.env, token, store, report);
        } catch (error) {
          if (error.status === 401) throw new NonRetryableError(reconnectMessage);
          throw error;
        }
        await store.markCreate("created", { issueUrl });
        await store.published();
      });
    } catch (error) {
      await step.do("record failure", () => store.fail(error.message.includes(reconnectMessage)));
      throw error;
    } finally {
      await step.do("clean up unpublished files", async () => {
        const report = await store.read();
        await clips.delete(draftKey(id));
        if (report.state !== "published") await clips.delete(publishedKey(id));
      });
    }
  }
}
