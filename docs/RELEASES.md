# Releases

GHub releases are built by GitHub Actions from version tags.

## Create a Release

1. Make sure `main` is green in CI.
2. Update user-facing docs if behavior changed.
3. Create and push a semantic version tag:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

The `Release` workflow builds `GHub.app`, packages it as
`GHub-<version>-macOS.zip`, writes a SHA-256 checksum, and creates a GitHub
Release with generated release notes.

## Versioning

`build-app.sh` reads these environment variables:

- `VERSION`: `CFBundleShortVersionString`, usually the tag without the leading
  `v`
- `BUILD_NUMBER`: `CFBundleVersion`, usually the GitHub Actions run number
- `BUNDLE_ID`: defaults to `com.bowanglan.ghub`
- `CODE_SIGN_IDENTITY`: defaults to `-` for ad-hoc signing

Example local release build:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 ./build-app.sh release
```

## Signing and Notarization

Current releases are ad-hoc signed. That is enough for local development, but
public macOS distribution should eventually use a Developer ID Application
certificate and Apple notarization.

Recommended follow-up:

- add `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and signing
  certificate secrets
- sign with Developer ID in the release workflow
- notarize the zipped app before publishing
