# MediaRemoteAdapter binaries

The vendored framework and test client are built from
[`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter),
tag `v0.7.6` (`3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`).

Both binaries are universal (`arm64` and `x86_64`) and use a macOS 14.0
deployment target to match Gojo. Build each architecture from the upstream
Objective-C sources with Xcode's `clang`, combine the results with `lipo`, and
ad-hoc sign the framework and test client. The release script replaces these
signatures with the configured Developer ID signature in the final app.

After rebuilding, verify the deployment target and adapter handshake:

```bash
xcrun vtool -show-build \
  MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
xcrun vtool -show-build MediaRemoteAdapterTestClient
/usr/bin/perl mediaremote-adapter.pl \
  "$PWD/MediaRemoteAdapter.framework" \
  "$PWD/MediaRemoteAdapterTestClient" test
```
