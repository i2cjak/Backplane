# Backplane

Backplane is an agent-driven electronics workspace, forked from [T3 Code](https://github.com/pingdotgg/t3code). It combines coding-agent conversations with KiCad PCB, schematic, Gerber, and 3D inspection across web, desktop, and mobile.

## Install

Download an installer for your system from [Backplane Releases](https://github.com/i2cjak/Backplane/releases). Each release lists its supported platforms. Installers include the desktop app, Chromium browser, server, Python, and the matching Backplane KiCad runtime with standard libraries.

Open Backplane and configure the coding provider you use. Provider accounts and credentials are your own. Berkeley Mono is used when installed on your system; the font is not redistributed with Backplane.

See [install and first run](docs/user/install.md), [KiCad views](docs/user/kicad.md), and [remote access](docs/user/remote-access.md). Open KiCad, FreeCAD, or Blender from the thread add menu to inspect the current project.

## Develop

Use the Node.js version in `package.json` and [Vite+](https://viteplus.dev/guide/).

```sh
git clone https://github.com/i2cjak/Backplane.git
cd Backplane
vp i
vp run dev
```

Open the pairing URL printed by the development server. Source builds use your local KiCad installation unless a Backplane runtime is configured. Viewer-tab changes are tracked separately from the app's release and appearance work.

Backplane installs alongside T3 Code. It uses its own application identity, `backplane://` links, and `~/.backplane` data directory. It never imports another app’s conversations or credentials automatically. Android uses `works.backplane.app`. Cloud integrations are opt-in; local and direct remote connections work without them.

## Documentation

Full docs live in [docs/](./docs). There's no docs site yet.

- [Install and first run](./docs/user/install.md)
- [Permission modes](./docs/user/permission-modes.md)
- [Keyboard shortcuts](./docs/user/keybindings.md)
- [Project settings](./docs/user/project-settings.md)
- [Remote access from a phone or another machine](./docs/user/remote-access.md)
- [Keeping app and server in sync](./docs/user/updating.md)
- [Source control integrations](./docs/user/source-control.md)
- Multiple accounts: [Codex](./docs/user/providers-codex.md) · [Claude](./docs/user/providers-claude.md)
- [Run Backplane as a background service](./docs/user/background-service.md)

Building from source? Start at [docs/internals/overview.md](./docs/internals/overview.md).

See [release operations](docs/operations/release.md) for runtime staging and publishing. Original licenses and upstream attribution remain in this repository and the [Backplane KiCad fork](https://github.com/i2cjak/Backplane_KiCad).
