# Drive CAD with your own MCP

This inspect overlay is meant to be extended. It is not locked to one CAD stack.

Backplane inspects whatever `.backplane.json` points at. The coding agent drives whatever MCP you attach. KiCad, FreeCAD, and Blender are the three used to prove that split. They are not a closed list.

Swap a server, rename the MCP key, or add another domain. Keep the inspect pointers. That is the same move as driving KiCad with your own MCP instead of Backplane's stock KiCad path.

FreeCAD and Blender inspect sit next to KiCad in the right-panel add menu. They only reread saved files. They do not launch those apps. Attach an MCP in the agent's config and Backplane starts it with the provider session. Backplane does not vendor a KiCad, FreeCAD, or Blender MCP. Extra CAD domains stay in the `drivers` map until they earn their own add-menu row.

## Driver contract

`.backplane.json` can name drivers next to inspect pointers. Domain keys are open. `mcp` is required. `reference` and `mutations` are optional labels for the agent.

```json
{
  "pcb": "hardware/controller.kicad_pcb",
  "schematic": "hardware/controller.kicad_sch",
  "enclosure": {
    "params": "mech/enclosure-params.json",
    "solids": {
      "BASE": "mech/BASE.stl"
    }
  },
  "product": {
    "still": "mech/product-render.png"
  },
  "drivers": {
    "kicad": {
      "mcp": "kicad",
      "reference": "https://github.com/mixelpixx/KiCAD-MCP-Server",
      "mutations": ["edit-board"]
    },
    "freecad": {
      "mcp": "freecad",
      "reference": "https://github.com/neka-nat/freecad-mcp",
      "mutations": ["edit-enclosure"]
    },
    "blender": {
      "mcp": "blender",
      "reference": "https://github.com/ahujasid/blender-mcp",
      "mutations": ["edit-scene"]
    }
  }
}
```

`mcp` is the server key in the agent's MCP config. Extra domains are allowed. A later CAD tool is another key, not a Backplane fork.

## References used to prove the overlay

These are drop-in examples, not Backplane dependencies. Replace any row.

| Domain  | MCP server key | Public reference                                                                                                              | Install hint                                                                            |
| ------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| KiCad   | `kicad`        | [mixelpixx/KiCAD-MCP-Server](https://github.com/mixelpixx/KiCAD-MCP-Server)                                                   | clone, `npm install`, `npm run build`, point `args` at `dist/index.js`                  |
| FreeCAD | `freecad`      | [neka-nat/freecad-mcp](https://github.com/neka-nat/freecad-mcp) ([PyPI `freecad-mcp`](https://pypi.org/project/freecad-mcp/)) | `uvx freecad-mcp` or `uv tool install freecad-mcp`, plus the FreeCAD addon in that repo |
| Blender | `blender`      | [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp) ([PyPI `blender-mcp`](https://pypi.org/project/blender-mcp/)) | `uvx blender-mcp`, enable the Blender add-on, start the socket from the viewport        |

A client config that matches those keys looks like this. Use your own paths and Python.

```json
{
  "mcpServers": {
    "kicad": {
      "command": "node",
      "args": ["KiCAD-MCP-Server/dist/index.js"]
    },
    "freecad": {
      "command": "uvx",
      "args": ["freecad-mcp"]
    },
    "blender": {
      "command": "uvx",
      "args": ["blender-mcp"]
    }
  }
}
```

Put that in the agent's MCP config for the thread. After the MCP writes files, the inspect tabs reread them.

If you already drive KiCad with a different server, keep it. Change `"mcp"` and `"reference"`. Leave the other rows as a template for the next domain.
