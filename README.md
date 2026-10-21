# Switchboard

A free Mac menu bar app that shows every localhost port you have open, with the project it belongs to. Find what is using port 3000, then open, restart, read logs, share or stop it in one click.

[Website](https://destucr.github.io/Switchboard/) · [Download](https://github.com/destucr/Switchboard/releases/latest)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="380" alt="Switchboard listing ports grouped by project">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-map-dark.png">
    <img src="docs/screenshot-map-light.png" width="380" alt="Switchboard map of how servers connect">
  </picture>
</p>

## Features

- **Grouped by project.** Vite, Next.js, Laravel, Django, Docker, Postgres, Redis and more.
- **The right button for each server.** Open for web pages, Copy URL for APIs and databases.
- **See how your servers connect.** The map shows which server talks to which, and warns before you stop something others depend on.
- **Servers you stopped stay listed.** One click starts a whole project again, in the order its servers depend on each other.
- **Share your stack.** Save a `switchboard.json` into the repo. A teammate adds the folder and presses Start stack.
- **Port conflicts.** Type `3000` to see who has it. Start tells you when a port is taken and offers the next free one. Change port restarts a running server somewhere else, with Undo.

## Install

```sh
brew install --cask destucr/tap/switchboard
```

Or download the zip from [Releases](https://github.com/destucr/Switchboard/releases).

The app is not notarized yet, so macOS blocks it the first time. Open System Settings, go to Privacy & Security, scroll down and click Open Anyway. Or run this once:

```sh
xattr -dr com.apple.quarantine /Applications/Switchboard.app
```

## Command line

The cask also installs a `switchboard` command:

```sh
switchboard status [--json]    # what is running
switchboard export             # write switchboard.json from what you have run
switchboard start              # start the stack in order
switchboard stop               # stop it, front ends first
```

`switchboard.json` holds commands and dependencies only, never environment variables.

## Build

Needs macOS 14+ and Xcode or the Command Line Tools.

```sh
./build.sh install    # build, copy to /Applications, start
./scripts/check.sh    # build with no warnings, then the self-test
./release.sh minor    # check, bump, tag, publish, update the Homebrew cask (--dry-run first)
```

## Contributing

Versions, the changelog and the release checks are described in [RELEASING.md](RELEASING.md).

## License

MIT
