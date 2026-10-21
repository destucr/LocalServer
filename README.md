# Switchboard

A Mac menu bar app that shows every port you have open, with the project it belongs to. Open, restart, read logs, share or stop any of them in one click.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="470" alt="Switchboard popover listing ports grouped by project">
  </picture>
</p>

## Features

- **Grouped by project.** Vite, Next.js, Laravel, Django, Docker, Postgres, Redis and more.
- **The right button for each server.** Open for web pages, Copy URL for APIs and databases.
- **Servers you stopped stay listed** with a Start button.
- **Port checker.** Type `3000` to see if it is free and who has it.

## Install

```sh
brew install --cask destucr/tap/switchboard
```

Or download the zip from [Releases](https://github.com/destucr/Switchboard/releases). The app is not notarized yet, so right click it and choose Open the first time.

## Build

Needs macOS 14+ and Xcode or the Command Line Tools.

```sh
./build.sh install    # build, copy to /Applications, start
./release.sh 1.1.0    # bump version, tag, publish release, update the Homebrew cask
```
