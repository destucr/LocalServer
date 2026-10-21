# LocalServer

A macOS menu bar app that lists every local listening port (Vite, Laravel, Next.js, Docker, Postgres…) grouped by the project it belongs to. Open, restart, tail logs, share or stop any of them in one click.

## Build

Requires macOS 14+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
./build.sh           # build build/LocalServer.app
./build.sh run       # build and launch
./build.sh install   # build, copy to /Applications, launch
```

Debug helpers: `LocalServer --scan`, `LocalServer --act kill|restart <port>`.

Public tunnels need `cloudflared` or `ngrok` (`brew install cloudflared`).
