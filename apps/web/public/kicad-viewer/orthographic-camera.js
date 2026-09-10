const FIT_MARGIN = 1.15;

/** Keep the vertical world span stable while adapting the horizontal frustum. */
export function resizeOrthographicCamera(camera, aspect) {
  const safeAspect = Number.isFinite(aspect) && aspect > 0 ? aspect : 1;
  camera.left = -safeAspect;
  camera.right = safeAspect;
  camera.top = 1;
  camera.bottom = -1;
  camera.updateProjectionMatrix();
}

/** Fit a bounding sphere without changing the camera's perspective (there is none). */
export function fitOrthographicCamera(camera, radius, aspect, direction) {
  const safeRadius = Math.max(radius, Number.EPSILON);
  const safeAspect = Number.isFinite(aspect) && aspect > 0 ? aspect : 1;
  const margin = safeRadius * FIT_MARGIN;
  // The base frustum is one world unit high. Account for both axes so a
  // narrow viewport cannot clip the model at its initial fit.
  camera.zoom = Math.min(1 / margin, safeAspect / margin);
  const distance = Math.max(safeRadius * 4, 1);
  camera.position.copy(direction.clone().normalize().multiplyScalar(distance));
  camera.near = 0.001;
  camera.far = Math.max(distance + safeRadius * 2, safeRadius * 20, 1);
  camera.updateProjectionMatrix();
}
