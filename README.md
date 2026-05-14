# GHub

A small macOS menu-bar app that tracks the state of local Git repositories — branches,
working-tree status, ahead/behind, open pull requests, and CI checks — all in one
glanceable popover. It appears in the Dock and keeps a status item in the top
menu bar.

## What it shows

For each repo you've added:

| signal | source |
| --- | --- |
| current branch, dirty / untracked, ahead/behind | local `git` |
| all branches with upstream tracking and last commit time | local `git` |
| recent commits on the current branch | local `git` |
| open pull requests + their titles, draft state, head branch | `gh pr list` |
| CI checks per PR (success / pending / failure) | `gh` (statusCheckRollup) |

Click a PR to open it on GitHub. Click the status item to expand any repo for
details. A colored dot summarizes the repo (green ok, yellow ahead/behind,
orange dirty, red failing CI).

## Requirements

- macOS 14 or newer
- Swift 5.9+ toolchain (Xcode command line tools)
- [`gh`](https://cli.github.com) (`brew install gh`) and `gh auth login` once,
  if you want PR + CI data. The app shells out to your existing `gh` install;
  no GitHub credentials are stored by GHub.

`git` and `gh` are looked up from `/usr/bin`, `/usr/local/bin`, and
`/opt/homebrew/bin`.

## Build

```sh
./build-app.sh           # produces GHub.app (release, ad-hoc signed)
open GHub.app            # launches; Dock icon and status item appear
```

For development / iteration:

```sh
swift build              # debug build
swift run GHub           # runs in foreground; ⌃C to stop
```

## Usage

1. Click the menu-bar icon → **Add Repo…** → pick a local Git checkout.
2. The repo syncs immediately. Subsequent syncs run every 5 minutes by default
   (configurable in **Settings… → General**).
3. Click any repo in the list to expand its branches, PRs, and recent commits.
4. **Settings… → Repositories** lets you toggle per-repo sync, refresh on
   demand, or remove a repo (only from tracking — the folder on disk is
   untouched).

## Storage

A single SQLite file at:

```
~/Library/Application Support/ghub/ghub.sqlite
```

Schema: `repos`, `branches`, `commits`, `pull_requests`, `ci_checks`. The
**Settings → General** tab has a "Reveal database in Finder" button.

To start over, quit the app and `rm -rf ~/Library/Application\ Support/ghub`.

## Notes & limits

- Only GitHub remotes are recognized for PR/CI data (parsed from
  `remote.origin.url`). Non-GitHub repos still show local state.
- "Open" PRs only — closed/merged PRs are not retained.
- Up to 50 open PRs per repo; up to 30 recent commits on the current branch.
- Sync failures are silent — last known state stays visible.
