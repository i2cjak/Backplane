# View KiCad projects

Backplane includes KiStack's electronics skills automatically for every project and agent provider. Ask your agent to use them for schematics, symbols, footprints, BOM review, PCB review, exports, Gerbers, panelization, or product renders. No separate skill installation is needed.

After each message sent to an agent, Backplane checks for skill updates in the background. Updated skills become available on subsequent messages without rebuilding the app. If the connection is unavailable, Backplane keeps the last downloaded copy, or its bundled copy on first use.

The full desktop installer includes KiCad and Python. Other workflow tools, such as Blender, may still need installation on the connected environment.

Agents receive the selected KiCad executable and guidance for exports, ERC/DRC checks, and, when a matching Backplane fork is present, its headless API. The bundled CLI is placed first on the agent's executable search path. Explicit `BACKPLANE_KICAD_CLI` or `KICAD_CLI` settings take precedence; instructions identify that selected executable instead. Advanced IPC scripts may require an isolated Python environment and bindings generated from the linked fork revision.

This follows the connected environment: a phone or remote browser uses the KiCad available on its server, not a KiCad installation on the device. Restart Backplane after an upgrade so agent processes receive the updated runtime.

Open **KiCad**, **FreeCAD**, or **Blender** from a thread's right-panel add menu. They are sibling inspect surfaces, not tabs inside one another. KiCad shows PCB, schematic, Gerber, 3D, and STEP. FreeCAD shows saved enclosure solids. Blender shows saved product stills. Each panel follows the thread's workspace or worktree. It reads saved files without locking them; you can continue editing in the CAD app or through your agent.

On mobile, the thread toolbar has the same three inspect actions. Each opens a full-screen native web view. The viewer uses a short-lived session tied to the active environment; reconnect and tap **Retry** if that session expires.

For a workspace containing several boards, create `.backplane.json` at its root:

```json
{
  "pcb": "hardware/controller.kicad_pcb",
  "schematic": "hardware/controller.kicad_sch",
  "gerbers": ["build/gerbers"],
  "symbol": "hardware/lib/parts.kicad_sym",
  "symbolMember": "Controller_unit1",
  "footprint": "hardware/lib/parts.pretty/Controller.kicad_mod",
  "enclosure": {
    "params": "mech/enclosure-params.json",
    "solids": {
      "BASE": "mech/BASE.stl",
      "PLATE": "mech/PLATE.stl"
    }
  },
  "product": {
    "scene": "mech/blender-scene.json",
    "still": "mech/product-render.png",
    "loadViz": "mech/load-viz-materials.json"
  },
  "drivers": {
    "kicad": {
      "mcp": "kicad",
      "reference": "https://github.com/mixelpixx/KiCAD-MCP-Server"
    },
    "freecad": {
      "mcp": "freecad",
      "reference": "https://github.com/neka-nat/freecad-mcp"
    },
    "blender": {
      "mcp": "blender",
      "reference": "https://github.com/ahujasid/blender-mcp"
    }
  }
}
```

Paths are relative to the workspace. These assignments select the design shown in the viewer; the agent and viewer can use the same files. Without assignments, the viewer opens an unambiguous project and leaves tools, examples, and routing intermediates out of automatic selection. Use **Browse** to preview another workspace file, and **Return to assigned design** to clear that temporary choice. PCB and 3D share a selection, as do schematic and BOM. Only referenced child sheets load with the selected schematic.

Generated output is discovered even in Git-ignored folders. Saved changes refresh while the viewer is visible. The previous preview remains visible while an update is prepared. Changed 3D items transition into place without resetting the camera; reduced-motion preferences disable this animation. Gerbers show the existing generated package; editing the board does not regenerate that package.

Use **STEP** to inspect `.step` and `.stp` models. The project picker lists the most recently edited files first; **Open file** also accepts a file from your device without uploading it. Drag to rotate, pinch or scroll to zoom, and use **Fit model** to restore the view. STEP previews run in the viewer and support files up to 100 MB.

Select a STEP part in the model or the collapsible parts tree, then adjust its opacity to inspect what is behind it. Selecting an assembly applies opacity to its parts together. Restore opacity to make the selection solid again; **Esc** clears the highlight. The camera and opacity choices remain when switching tabs or refreshing the same file.

Both board and STEP previews use orthographic projection with cel-shaded colors and outlines. Drag to tumble the model freely in any direction; **Top**, **Bottom**, and **Fit model** return to familiar views.

The 3D preview requires `kicad-cli` with GLB export on the environment running Backplane. The preview includes outer copper, pads, silkscreen, and translucent soldermask using the board’s stackup colors. Exports go into a separate temporary cache. The **FreeCAD** and **Blender** panels do not call `kicad-cli` and do not start those apps. They serve the saved STL/STEP/GLB solids, enclosure params JSON, product still, and load-viz images named in `.backplane.json`. Gerber rendering requires `python3` there. None of these operations modify the project.

The agent drives those apps through MCP you attach. The FreeCAD and Blender panels only show what that agent already wrote. `drivers` is an open map: extra domains are allowed, and any server can replace the examples. Backplane does not vendor a KiCad, FreeCAD, or Blender MCP. Name the server keys you already run, the same way you can drive KiCad with your own MCP instead of the stock KiCad path. See [Drive CAD with your own MCP](./cad-mcp.md).

Use **Open KiCad viewer in browser** to let your agent inspect and interact with the viewer through the collaborative browser. Its link grants temporary read-only access to this workspace; reopen the panel after the link expires or the server restarts. The `backplane-viewer` agent skill includes a helper for finding and configuring project files.

The PCB and schematic use the bundled American Embedded Dark theme. Find a component by its reference (such as `U1`), or enable **Net** to search by net name. Selected components have a subtle glow beneath their geometry. Select a component and use **Show in schematic/PCB** to highlight its counterpart without losing the other view’s camera. Use the PCB layer panel to show or hide copper, silkscreen, solder mask, fabrication, and board layers.

Activate **Cross-probe** with its toolbar button or **X**, then click a component to switch to its highlighted counterpart in the schematic or PCB. Press **Esc** to return to normal selection. The shortcut leaves text entry alone.

Select a pad, track, wire, or net label and press **H** to highlight the whole net. **Highlight net** performs the same action on touch devices. Press **Esc** to clear the highlight.

In Gerbers, use the arrow buttons or left/right arrow keys to flip layers. **Copper stack**, **Front fabrication**, and **Back fabrication** combine aligned layers from the current fabrication set. Use the layer panel to choose individual layers. Each layer is cached independently, so changing one saved Gerber keeps the other layers in place. Fabrication presets use available silkscreen, fabrication, and paste artwork; they are not a component BOM or a substitute for populated assembly inspection.

Use **Tools** inside the KiCad viewer to open **BOM**, **Footprints**, **Symbols**, or **EMerge / Analysis**. Close an optional tab with its close button and reopen it from the same menu. These views are shared by web, desktop, and mobile.

The BOM follows the selected schematic and the current saved BOM settings in its matching `.kicad_pro`: visible fields, column labels, grouping, sorting, filtering, DNP handling, and output formatting. Changes saved in KiCad refresh the table. Select the root schematic when using a hierarchical design. If the matching project has no saved BOM settings, the viewer explicitly reports that it is using KiCad defaults. Search the table or download the exported BOM. Export runs against a temporary copy and leaves project files untouched; it is a preview, not a manufacturing release check.

Footprints (`.kicad_mod`) and symbol libraries (`.kicad_sym`) are discovered within the workspace. Select a library and then a symbol/unit to inspect its SVG preview. The BOM and library previews require `kicad-cli` on the connected environment.

The analysis view creates a planar antenna starter specification with feed and ground contacts and one or two target bands for the antenna-rl workflow. Export or copy the specification for your agent to use. EMerge results can be embedded by adding an `analysisUrl` to `.backplane.json`, using a dashboard address reachable from every device that will open the viewer:

```json
{
  "analysisUrl": "https://antenna-dashboard.example.com"
}
```

The dashboard service must allow embedding; **Open dashboard** opens it separately. The openEMS option currently prepares a specification only; an openEMS execution adapter is not included. Exporting a specification does not start a solver or training job or qualify an antenna design.
