# Backplane.app

The Mac app: the hub and its web client in a window of its own. A Mac has no
X11, so the native window (`src/app/`) is not built there; this shell shows
the web client instead, which every feature reaches (AGENTS.md: every
feature matches everywhere).

`main.swift` holds no product logic:

- finds a hub already running for the home (`<home>/hub.lock`, `<pid> <port>`,
  a live `backplane`) and uses it, or starts the bundled one
  (`Contents/Resources/backplane/backplane --home <home> --port 3787`, its
  output in `<home>/app.log`) and stops it on quit
- gives the hub the login shell's `PATH` (an app opened from Finder gets only
  the system's, and agents need `claude`, `git`, `gh`...)
- runs the hub with `BACKPLANE_NO_UPDATE`: the app updates as a whole, never
  file by file inside its bundle
- keeps the hub's pages in the window and opens every other link in the
  browser; Edit menu (copy and paste), zoom, reload, Hub Log, Open in Browser

`BACKPLANE_HOME` and `BACKPLANE_PORT` override the home and port (tests use a
temp home).

## Build

```sh
scripts/build.sh                 # dist/: the hub, web client, helpers
scripts/package-mac.sh v0.11.0   # dist/Backplane.app and its .app.zip
```

`release.yml`'s darwin job does the same and publishes
`backplane-<version>-darwin-arm64.app.zip`. The app is ad-hoc signed, not
notarized: a downloaded copy opens the first time from System Settings >
Privacy & Security > Open Anyway. Notarizing needs a Developer ID
certificate in the workflow's secrets.
