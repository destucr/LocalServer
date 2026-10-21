# Changelog

All notable changes to Switchboard. The format follows [Keep a Changelog](https://keepachangelog.com), and versions follow [Semantic Versioning](https://semver.org). See [RELEASING.md](RELEASING.md) for the rules.

## [Unreleased]

### Added
- Starting a server whose port is taken now says who holds it and offers to start on the next free port. Start stack and Start project skip taken ports and tell you which.
- MIT license.

### Changed
- Motion: rows, panels and map nodes slide and settle with springs instead of fading, the list and the map switch with a slide, and buttons press in.
- Install notes: the first launch steps now match current macOS (Privacy & Security, Open Anyway).

## [1.5.0] - 2026-10-21

### Added
- Change port. Restarts a running server on another port, with Undo. It edits the port flag it recognises (Vite, Next.js, Laravel, Flask and others) and falls back to `PORT`.

## [1.4.1] - 2026-10-21

### Fixed
- `switchboard version` printed "dev" when run through the Homebrew link.

## [1.4.0] - 2026-10-21

### Added
- Undo after Stop and after Stop all.
- Right-click menus on rows, project headers and map nodes.
- Project boxes on the map.
- Map: drag empty space to pan, pinch or buttons to zoom, click to deselect, connection counts.

## [1.3.0] - 2026-10-21

### Added
- Shareable stack: `switchboard.json` and a `switchboard` command line (`status`, `start`, `stop`, `export`, `why`).
- Map icons by server type, draggable nodes with saved positions.
- Keyboard navigation and VoiceOver support.

## [1.2.0] - 2026-10-21

### Added
- Stack map: which servers talk to which, broken links from `.env`, a warning before stopping a server others use.
- Start stack: bring a project back in dependency order.
- "Why did it stop?" from exit status, crash reports, last output, port takeover and closed terminals.

## [1.1.0] - 2026-10-21

### Changed
- Renamed the app from LocalServer to Switchboard.

## [1.0.0] - 2026-10-21

### Added
- First release. Menu bar list of every listening port with its project, Open, Restart, Logs, Share and Stop.
