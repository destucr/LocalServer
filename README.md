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
- **Port checker.** Type `3000` to see if it is free and who has it.

## Install

```sh
brew install --cask destucr/tap/switchboard
```

Or download the zip from [Releases](https://github.com/destucr/Switchboard/releases). The app is not notarized yet, so right click it and choose Open the first time.

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
./release.sh 1.1.0    # bump version, tag, publish release, update the Homebrew cask
```

## License

MIT
