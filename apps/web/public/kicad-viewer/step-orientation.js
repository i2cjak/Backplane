// STEP and KiCad's GLB exporter use Z-up coordinates; the shared viewer uses
// Y-up coordinates. Rotate the imported scene so board-top remains viewer-top.
export const STEP_TO_VIEWER_ROTATION_X = -Math.PI / 2;

export function orientStepScene(scene) {
  scene.rotation.x = STEP_TO_VIEWER_ROTATION_X;
  return scene;
}
