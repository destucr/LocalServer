# LocalServer

A small Mac app that lives in your menu bar and shows every port your computer is listening on. Vite, Laravel, Next.js, Docker, Postgres, whatever you have running. Each one is shown with the project it belongs to, and you can open, restart, read the logs, share or stop it with one click.

<p align="center"><img src="docs/screenshot.png" width="420" alt="LocalServer popover listing ports grouped by project"></p>

## What you get

- **Ports grouped by project.** The app looks at where each process was started to find its project.
- **It knows what is running.** Vite, Next.js, Nuxt, Astro, Laravel, Django, Rails and more. Databases like PostgreSQL, MySQL, Redis and MongoDB too.
- **Docker support.** Containers show up on their ports, grouped by compose project.
- **A clear button on every row.** If the port serves a web page you get **Open**. If it is an API or a database you get **Copy**.
- **More actions when you hover a row:**
  - **Restart** brings the process back with the same command, folder and environment.
  - **Logs** follows the log file in Terminal (or `docker logs -f` for containers).
  - **Share** copies the localhost or network URL, or starts a public tunnel.
  - **Stop** shuts it down. For databases and containers it asks you to click twice.
- **Port checker.** Type a port number like `3000` in the search box. It tells you if the port is free, who is using it, and which port to use next.
- **Global shortcut.** Press `Control + Option + P` from anywhere. The search box is ready, so type and press Return.
- **Quiet by default.** System apps like ControlCenter and Raycast are hidden. You can turn them on from the gear menu.

The little orange wifi icon means the server is open to your whole network, not just your Mac.

## Install

With Homebrew:

```sh
brew install --cask destucr/tap/localserver
```

Or download the zip from [Releases](https://github.com/destucr/LocalServer/releases), move the app to `/Applications`, and right click it and choose Open the first time. The app is not notarized yet, so macOS asks once.

## Build it yourself

You need macOS 14 or newer and Xcode or the Command Line Tools.

```sh
./build.sh           # build the app into build/LocalServer.app
./build.sh run       # build and start it
./build.sh install   # build, copy to /Applications and start it
```

After you change the code, run `./build.sh install` again. It stops the running app, replaces the old one and starts the new one.

"Launch at login" only works when the app is in `/Applications`. The app is not sandboxed, because it needs to look at your processes and stop them.

## Releasing

Put your changes in a commit, then run:

```sh
./release.sh 1.1.0
```

That bumps the version, builds the zip, tags it, pushes, creates the GitHub release and updates the Homebrew cask. The version number lives in the `VERSION` file and shows up in the About item of the gear menu.

## Handy commands

```sh
LocalServer --scan                     # print what the app sees
LocalServer --act kill|restart <port>  # stop or restart a port from the terminal
LocalServer --screenshot out.png       # draw the popover with sample data
```

Public tunnels need `cloudflared` or `ngrok`. The easy way is `brew install cloudflared`.
