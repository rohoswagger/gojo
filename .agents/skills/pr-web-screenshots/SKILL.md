---
name: pr-web-screenshots
description: Attach verified web screenshots to every pull request.
---

# Pull request web screenshots

Every Gojo pull request must show the built web UI on GitHub. A PR is not complete when screenshots exist only on disk, in browser-tool output, or in a local artifact directory.

## When to use

Use this skill before creating any Gojo pull request and before reporting an existing PR as ready for review.

## Required evidence

- Attach at least one screenshot of the built web UI to every PR.
- For a visual web change, show every materially changed route or state.
- Add desktop and mobile screenshots when responsive behavior changed.
- For a non-visual or non-web change, attach a current web smoke screenshot and label it `No visual changes expected`.
- Use real rendered output from the PR branch, never a mockup or an older production screenshot.
- Exclude secrets, private user data, browser chrome containing accounts, and local filesystem paths.

## Procedure

1. **Build the branch.** Run the repository's complete web verification and production build. Continue only when it passes.
2. **Serve the built artifact.** Start the exported web UI locally using the project workflow. Confirm the target route returns HTTP 200.
3. **Capture representative states.** Use the browser tool at a stable viewport. Wait for fonts, images, and layout to settle. Capture the full relevant page or a crop that includes enough surrounding UI to identify the state.
4. **Inspect the pixels.** Check for clipping, missing assets, broken typography, accidental personal data, and incorrect state. Rebuild and recapture if anything is wrong.
5. **Attach on GitHub.** Put the image under `## Screenshots / recording` with the route, viewport, and state. Prefer uploading through GitHub's PR editor or comment composer so GitHub creates a durable `github.com/user-attachments/assets/...` URL. When interactive upload is unavailable, copy the inspected image to `.github/pr-screenshots/<branch-slug>/`, commit it on the PR branch, and embed an absolute `raw.githubusercontent.com` URL pinned to that commit. A local path does not satisfy this step.
6. **Verify the external write.** Read the PR body or comment back from GitHub. Confirm the image URL is present, returns HTTP 200, and the rendered image is visible. Do not claim the PR is ready until this succeeds.
7. **Keep evidence current.** If later commits materially change the UI, replace or supplement the screenshot and verify the updated attachment.

## PR body format

```markdown
## Screenshots / recording

**Desktop — `/affected-route/` — 1440 × 900**

![Descriptive alt text](https://github.com/user-attachments/assets/<id>)
```

For non-visual work:

```markdown
## Screenshots / recording

No visual changes expected. Web smoke check from this branch:

![Gojo homepage smoke check](https://github.com/user-attachments/assets/<id>)
```

## Pitfalls

- Do not attach screenshots from production when the PR branch can be rendered locally.
- Do not commit one-off screenshots outside `.github/pr-screenshots/`; use GitHub user attachments when interactive upload is available.
- Do not use a screenshot tool's local `MEDIA:` path in the PR body.
- Do not open the PR first and promise screenshots later. Capture and upload them in the same PR workflow.
- If both GitHub upload and the committed-snapshot fallback are blocked, stop and report the blocker. Never silently omit the screenshot.

## Verification

The workflow is complete only when all are true:

- The branch build passed.
- Each screenshot came from the current PR branch.
- The screenshot was visually inspected.
- GitHub contains a remote user-attachment URL in the PR body or a PR comment.
- The PR was read back after upload and the image renders.
