# destination limits and mark usage research

accessed 2026-10-24. upload-limit claims and account caveats rechecked against the same official GitHub and Discord pages on 2026-10-25; the 10 MB / 20 MB claims remain unchanged. this is a source snapshot for iteration 3. verify again before release.

## published upload limits

| destination | supported claim for a preset label | scope and conditions |
| --- | --- | --- |
| Discord | 20 MB maximum upload for non-Nitro accounts | Discord's attachment FAQ says it is experimenting with different upload limits and selected users may upload larger files. Nitro Basic is listed at 50 MB and Nitro at up to 1 GB. Discord says the limit is checked before compression; its upload instructions include GIFs. do not imply 20 MB is universal across accounts or that an optimizer can guarantee acceptance. |
| GitHub | 10 MB maximum for images and GIFs | this is the attachment limit for issue, pull request, and comment uploads described by GitHub's attaching-files documentation. it is distinct from repository file storage, video limits, and other file types. the documented value is not plan-dependent for image/GIF attachments. |

the sources state MB, not an exact byte threshold or binary MiB conversion. the architect chose a 90% target in decimal MB: 9 MB for GitHub and 18 MB for Discord non-Nitro. these are optimization targets, not guaranteed upload acceptance.

## mark usage notes

- Discord says its logo may be used in color, black, or white; its symbol should be used only when the Discord brand is clearly visible or already established. the page says not to edit, change, distort, recolor, or reconfigure the logo. it also says permission is required for Discord marks/assets except as permitted by the guidelines. the page does not explicitly approve an optimizer destination button; do not infer approval from the existence of the mark or a text label.
- GitHub says its logo can be added to third-party applications in some scenarios and directs readers to the GitHub Logos and Usage page. that page says the standalone Invertocat is for GitHub-owned environments or where the brand is clearly established; a permitted logo can be used to show a project integrates with GitHub, and marks must not imply affiliation or endorsement. it also says not to modify the mark and to contact GitHub about authorized uses. the optimizer target button is not explicitly addressed as an authorized use, so logo inclusion needs its own review/clearance before release.
- the architect chose destination names with native symbols for first release; do not bundle third-party marks unless written permission is obtained. this note does not select gifferent artwork or settle its visual identity approval.

## official sources

- [Discord File Attachments FAQ](https://support.discord.com/hc/en-us/articles/25444343291031-File-Attachments-FAQ) — updated September 30, 2026; accessed 2026-10-24. see the upload limit, experiment notice, GIF attachment behavior, and account tiers.
- [GitHub Docs: Attaching files](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files) — accessed 2026-10-24. see the discussion attachment scope, 10 MB image/GIF limit, and supported types.
- [Discord Brand Guidelines](https://discord.com/branding) — accessed 2026-10-24. see logo and symbol use, alteration restrictions, and legal brand guidelines.
- [GitHub Logo Policy](https://docs.github.com/en/site-policy/other-site-policies/github-logo-policy) and [GitHub Brand Toolkit: Logo](https://brand.github.com/foundations/logo) — accessed 2026-10-24. see third-party application scenarios, permitted use examples, restrictions, and contact for authorized uses.
