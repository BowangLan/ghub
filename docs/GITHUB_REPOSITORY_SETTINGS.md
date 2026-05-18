# GitHub Repository Settings

These are the recommended settings for a small public macOS desktop app repo.
They can be applied in the GitHub UI or later through `gh`/API automation.

## General

- Description: `A macOS menu-bar app for tracking local GitHub repo status.`
- Website: leave blank until there is a product page
- Topics: `macos`, `swift`, `swiftui`, `github`, `menu-bar`, `desktop-app`
- Features: enable Issues, Discussions, and Projects only if you intend to use
  them; disable Wiki unless it has real content

## Pull Requests

- Enable squash merging
- Disable merge commits
- Disable rebase merging unless linear history by rebase is preferred
- Enable auto-delete head branches
- Enable "Always suggest updating pull request branches"

## Branch Protection

Protect `main`:

- require a pull request before merging
- require status checks to pass before merging
- required check: `Swift build`
- require branches to be up to date before merging
- require conversation resolution before merging
- block force pushes
- block deletions

For a solo repo, do not require review count unless you want to force an
explicit review loop.

## Actions

- Allow GitHub Actions and reusable workflows
- Workflow permissions: read repository contents by default
- Allow GitHub Actions to create and approve pull requests only if automation
  needs it later

## Security

- Enable private vulnerability reporting
- Enable Dependabot alerts
- Enable Dependabot security updates
- Enable secret scanning and push protection if available for the repo

## Releases

- Release tags should use `vMAJOR.MINOR.PATCH`, for example `v0.1.0`
- Keep generated release notes enabled
- Attach `GHub-<version>-macOS.zip` and its `.sha256` checksum
