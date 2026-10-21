# Releasing

How a change becomes a release, and what has to be true before it ships.

## Versions

Switchboard uses [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

| Bump | When | Examples |
| --- | --- | --- |
| **patch** | Fixes only. Nothing new to learn. | A crash, a wrong label, a CLI bug. |
| **minor** | New things, nothing removed or changed in a way that breaks. | A feature, a menu item, a new command. |
| **major** | Anything that can break what people already have. | A change to the `switchboard.json` format, a removed or renamed CLI command or flag, dropping a macOS version. |

If a release has both a fix and a feature, it is a minor release. If you are unsure between two, pick the bigger one.

## Every change

1. Add a line to **`## [Unreleased]`** in `CHANGELOG.md`, under `Added`, `Changed`, `Fixed`, `Removed` or `Breaking`. Write it for a user, in plain words. A change with no line does not ship.
2. Run `./scripts/check.sh`. It must pass: a clean build with no warnings, and `--selftest`.
3. If the UI changed, regenerate the screenshots (`Switchboard --screenshot docs/screenshot-light.png`, then `dark`, `map`, `map dark`) and check them by eye. Update the README and `docs/index.html` if the change is something a user would look for.
4. Commit with a plain message. No attribution trailers.

## Release checklist

Run `./release.sh patch`, `./release.sh minor`, `./release.sh major`, or `./release.sh 1.6.0`. Add `--dry-run` first to see what it would do without changing anything.

The script refuses to continue unless:

- you are on `main`, the tree is clean, and you are not behind `origin/main`;
- the new version is valid, higher than the current one, and not already tagged;
- `[Unreleased]` has entries, and the bump matches them (`Added` needs at least minor, `Breaking` needs major);
- `./scripts/check.sh` passes.

Then it writes the version, moves `[Unreleased]` under the new version and date, builds, tags, pushes, creates the GitHub release with that changelog section as the notes, updates the Homebrew cask, and checks the release and the cask agree.

## Before you tell anyone

The checks cannot see everything. Open the built app and go through this by hand:

- [ ] The popover opens from the menu bar icon and from the hotkey, and closes cleanly.
- [ ] Open, Restart, Logs, Stop and Undo work on a real server.
- [ ] The right-click menu opens on a row and on a map node.
- [ ] Start on a server whose port is taken offers another port.
- [ ] Light mode, dark mode, and Reduce Motion look right.
- [ ] `switchboard status` and `switchboard version` work from a terminal.
- [ ] A fresh `brew upgrade --cask destucr/tap/switchboard` installs the new version and it launches.

## If a release is bad

Do not move or delete the tag. Fix forward with a patch release. If the release is dangerous, mark it as a pre-release on GitHub and revert the cask version in `destucr/homebrew-tap` so `brew upgrade` stops offering it.
