# Contributing

Thanks for contributing to Gojo.

## License context

Gojo is presently maintained as a GPLv3, fork-derived project. If your
change introduces code, assets, or documentation from another source,
make sure the source is compatible with this repository's licensing
posture and update [`THIRD_PARTY_LICENSES`](./THIRD_PARTY_LICENSES) or
[`NOTICE.md`](./NOTICE.md) when needed.

## Scope

Useful contributions include:
- bug fixes
- new notch modules or interactions
- accessibility improvements
- documentation updates
- polish for the Gojo experience as a multi-tool macOS notch hub

## Before you start

- Search existing issues first
- Open an issue before starting major work
- Base code changes on `dev` when that branch is active for ongoing development

## Localizations

Gojo does not currently use an external localization sync workflow. If your PR touches user-facing strings, keep translation-only churn out of the same PR unless the localization work is intentional and coordinated.

## Setup

```bash
git clone https://github.com/{your-username}/gojo.git
cd gojo
open Gojo.xcodeproj
```

## Pull requests

Please include:
- a clear summary of the change
- why the change was made
- screenshots or recordings for UI changes
- links to related issues when relevant

## Verification

Before opening a PR, make sure the app still builds and launches locally.

## Getting help

If you are blocked, open an issue in the repository with the context needed to reproduce the problem.
