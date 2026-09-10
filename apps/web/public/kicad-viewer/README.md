# KiCad viewer vendor bundle

This directory contains the browser viewer artifacts used by Backplane's KiCad
views. The retained native controllers reuse the mature KiCanvas geometry
engine/parser and the bundled Three.js assets; they keep the renderer and GPU
context alive while saved sources are replaced. The ECAD bundle manifest records
the upstream and adapter commits for those assets.

The `ecad-viewer.js` and `parser.worker.js` artifacts provide the KiCanvas
native KiCad schematic and PCB engine. `3d-viewer.js`, Three.js, and its add-ons
provide the 3D assets loaded by the ECAD element. These files are read-only
browser assets: the viewer receives snapshots of file contents and never opens
a KiCad source file for writing or locking.

The Gerber camera hook at `src/kicad/vendor/fabrication-viewport.ts` and the
server renderer at `apps/server/src/kicad/vendor/prismGerber.ts` retain the
Apache-2.0 KiCAD-Prism parser/renderer, with attribution and the vendor license
kept beside the source. `runtime.html`, `runtime.js`, `retained-native-viewer.js`,
`model-appearance.js`, and `schematic-sizing.js` are Backplane adapters. The
native controllers retain parsed layers and cameras across updates, use
highlight overlays for selection, and keep layer colors available to the UI.

The model appearance adapter uses unlit materials and KiCad's exported colors
and opacity for fast, stable previews. It does not add resin clearcoat or alter
the source GLB's layer palette.

## Bundled color theme

`american-embedded-dark.json` is the American Embedded Dark KiCad color theme,
copied from the [American Embedded KiCad Repository](https://github.com/American-Embedded/American_Embedded_KiCad_Repository/tree/main/packages/themes/american-embedded-dark)
at version 1.0.0. It is included under the theme's CC BY 4.0 license; American
Embedded is the author. The original metadata is available in the repository's
`packages/themes/american-embedded-dark/metadata.json`; see the
[Creative Commons Attribution 4.0 license](https://creativecommons.org/licenses/by/4.0/).
