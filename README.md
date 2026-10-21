# LocalServer

A Mac menu bar app that shows every port you have open, with the project it belongs to. Open, restart, read logs, share or stop any of them in one click.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="470" alt="LocalServer popover listing ports grouped by project">
  </picture>
</p>

## Features

- **Grouped by project.** Vite, Next.js, Laravel, Django, Docker, Postgres, Redis and more.
- **One clear button per row.** **Open** for web pages, **Copy URL** for APIs and databases.
- **Hover a row** to restart, read logs, share (link or QR code for your phone), stop, pin or rename.
- **Stopped servers stay listed** with a **Start** button. Whole project actions are in the project menu.
- **Port checker.** Type `3000` to see if it is free, who has it, and the next free port.
- **Alerts** when a server stops by itself. Shortcut: `Control + Option + P`.

## Install

```sh
brew install --cask destucr/tap/localserver
```

Or download the zip from [Releases](https://github.com/destucr/LocalServer/releases). The app is not notarized yet, so right click it and choose Open the first time.

## Build

Needs macOS 14+ and Xcode or the Command Line Tools.

```sh
./build.sh install    # build, copy to /Applications, start
./release.sh 1.1.0    # bump version, tag, publish release, update the Homebrew cask
```
