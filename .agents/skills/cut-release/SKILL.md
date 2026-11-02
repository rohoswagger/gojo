---
name: cut-release
description: Build, sign, notarize, publish, or roll back a Gojo release. Use for release tags, DMG publication, Sparkle updates, and the release pipeline.
---

# Release Gojo

Read `RELEASING.md` before acting. It defines the current signing, hosting, and verification procedure. Use `scripts/release.sh` for a new release and its pinned packaging dependencies. Never create a GitHub Release or attach a DMG to GitHub.

## Resolve the requested outcome

- A request to release, publish, ship a version, or publish its DMG includes distribution to existing users through Sparkle. Use `make release VERSION=X.Y.Z ARGS=--public`. Do not stop after tagging or uploading the DMG.
- An explicitly private or build-only request uses the script's private default or `make release-dry`. State that existing installs will not discover it.
- An explicitly source-tag-only request creates only the source tag. State that no binary or update entry was published.
- An explicitly download-only request can omit Sparkle. Do not infer that exception from the word "DMG" alone.

The script defaults to private for historical distribution reasons. That CLI default does not change a user's request to publish. Existing authorization to publish covers the DMG and update entry; do not ask again just because `--public` is needed. If scope truly remains unclear, resolve it before external writes.

## Prepare a new version

1. Verify current remote main, tags, published version, and installed update channel. Do not downgrade or overwrite an immutable versioned artifact.
2. Add the version's CHANGELOG entry and bump every MARKETING_VERSION occurrence before creating its source tag. Use the repository's PR workflow for changes.
3. Build a clean reviewed source revision. Record source commit, version, monotonically increasing build number, architecture, minimum macOS version, bytes, SHA-256, and Sparkle signature.
4. Keep Developer ID signing, hardened runtime, nested-component entitlements, notarization, and stapling intact. Never fall back to ad-hoc signing for a public release unless the user explicitly requests it.
5. Publish the immutable `gojo-downloads/Gojo-X.Y.Z.dmg` and latest `gojo-downloads/Gojo.dmg` alias. Verify both public downloads against the notarized artifact.
6. Publish the signed appcast entry and verify the live feed as described below. A tag, upload, or website deployment alone is incomplete.

Credentials are in gitignored `.env.local`. Never print signing keys or other secrets. Preserve existing Sparkle keys. Read the Cloudflare and Wrangler skills before R2 operations; verify commands against current CLI help. The R2 account is `54b7185040a2db03ec87bee9cd65135f`.

## Publish an already built or tagged artifact

Do not rebuild, move the tag, change the build number, or replace a versioned DMG just to add a missing feed entry. Reuse the exact verified artifact and its recorded size, build number, URL, minimum OS, and Ed25519 signature. A signature from another build is invalid even if its marketing version matches.

If only a source tag exists, first build its exact source tree. Resolve missing release metadata explicitly and record any build-time version override. Preserve source correspondence and the pushed tag. Do not silently bypass signing or notarization checks to work around release-script preflight.

## Publish and verify Sparkle

1. Fetch the canonical live feed and repository appcast. Preserve older entries. Reject duplicate version entries or a non-increasing build number.
2. Use `.github/scripts/update_appcast.py` with the verified artifact metadata and CHANGELOG notes. Check the generated enclosure URL, length, signature, build, short version, and minimum OS against the packaged app and recorded evidence.
3. Download the enclosure URL and verify byte count, SHA-256, and Ed25519 signature against the public update key embedded in the shipped app.
4. For manual publication of an existing artifact, submit and merge the appcast through a PR. The current `scripts/release.sh --public` path commits the feed directly to main; if it already did so, verify that committed file instead of creating a duplicate PR. Publish the exact repository file with explicit non-cacheable metadata. Re-upload those same bytes if the script uploaded them without that metadata:

   ```bash
   CLOUDFLARE_ACCOUNT_ID=54b7185040a2db03ec87bee9cd65135f \
     npx wrangler@4 r2 object put gojo-downloads/appcast.xml --remote \
       --content-type application/xml --cache-control no-cache --file appcast.xml
   ```

5. Fetch `https://updates.trygojo.com/appcast.xml` and the legacy `https://trygojo.com/appcast.xml` redirect without a cache-busting query. Both must serve the new version, build, enclosure URL, length, and signature. Compare the live feed to the reviewed uploaded bytes. A successful R2 PUT or a cache-busted response alone is insufficient. Resolve stale caches before declaring completion.
6. Repeat artifact verification from the live enclosure. Exercise Check for Updates from an older installed app when practical and authorized. If that UI cannot be exercised, report that limitation separately from feed verification. Respect user exclusions such as no live microphone testing.

Modern installs read `updates.trygojo.com` directly from R2. Legacy installs use the HTTPS redirect at `trygojo.com/appcast.xml`. Do not rely on a GitHub Pages rebuild or an unrelated website deploy to publish the R2-backed feed.

## Completion gate

Before saying "published", verify all requested outcomes:

- Signed and notarized versioned DMG and latest alias download with the expected hashes.
- Live canonical and legacy feeds advertise the exact signed artifact, with older entries intact.
- Source tag and artifact correspondence are recorded; no tag was silently moved.
- Update discovery was exercised, or its untested UI status is stated explicitly.

A publication report includes the download link, version/build, verification results, and any remaining limitation. If interrupted after DMG upload, record **DMG uploaded; Sparkle publication pending** and resume the feed step. Do not call the release complete.

## Rollback and replacement

Treat shipped artifacts as immutable. A replacement normally gets a new version and increasing build number. Delete or move tags, overwrite historical DMGs, or remove feed entries only with explicit rollback or re-cut authorization. Merely adding a missing feed entry is not a re-cut.

For an authorized rollback, remove the affected feed entry through review, publish and verify both live feed paths, then repoint `Gojo.dmg` to a verified prior artifact. Preserve older feed entries. Remove the bad versioned object or tag only if that deletion is authorized. Installed copies cannot be remotely uninstalled.

## Local build failures

SPM and dmgbuild environments embed absolute paths. If the checkout moved, inspect stale package paths or venv shebangs before rebuilding task-owned caches. Do not delete unrelated user caches or model payloads. Check disk space when codesign reports an internal allocation error.

A notarized build also needs launch verification under the repository's safe development procedure. Use `GOJO_LICENSE=lifetime` for a debug launch and preserve the user's running production instance. Do not run an unqualified executable that can migrate shared licensing state. If launch testing is unavailable or excluded, state it; do not weaken signing or claim runtime proof from compilation.
