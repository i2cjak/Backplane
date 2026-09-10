import {
  DepthTexture,
  DepthFormat,
  Mesh,
  NearestFilter,
  NoBlending,
  OrthographicCamera,
  Scene,
  ShaderMaterial,
  UnsignedIntType,
  Vector2,
  Vector3,
  WebGLRenderTarget,
  PlaneGeometry,
} from "three";

// Render once to a depth-backed target, then find depth/color discontinuities
// in one bounded fullscreen pass. This keeps outline work independent of mesh
// count and avoids the memory/draw-call cost of per-mesh edge geometry.
export function createCelOutlinePass(renderer) {
  const target = new WebGLRenderTarget(1, 1, {
    depthBuffer: true,
    stencilBuffer: false,
    minFilter: NearestFilter,
    magFilter: NearestFilter,
  });
  // The scene moves off the antialiased default framebuffer for outlining.
  // Preserve its edge quality with a bounded multisample target when available.
  target.samples = Math.min(4, renderer.capabilities.maxSamples);
  target.depthTexture = new DepthTexture(
    1,
    1,
    UnsignedIntType,
    undefined,
    undefined,
    undefined,
    NearestFilter,
    NearestFilter,
    0,
    DepthFormat,
  );

  const material = new ShaderMaterial({
    uniforms: {
      colorBuffer: { value: target.texture },
      depthBuffer: { value: target.depthTexture },
      texelSize: { value: new Vector2(1, 1) },
      depthThreshold: { value: 0.0025 },
      colorThreshold: { value: 0.16 },
      outlineColor: { value: new Vector3(0.002, 0.004, 0.005) },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = vec4(position.xy, 0.0, 1.0);
      }
    `,
    fragmentShader: `
      uniform sampler2D colorBuffer;
      uniform sampler2D depthBuffer;
      uniform vec2 texelSize;
      uniform float depthThreshold;
      uniform float colorThreshold;
      uniform vec3 outlineColor;
      varying vec2 vUv;

      void main() {
        vec4 base = texture2D(colorBuffer, vUv);
        float centerDepth = texture2D(depthBuffer, vUv).r;
        float depthEdge = 0.0;
        float colorEdge = 0.0;
        for (int y = -1; y <= 1; y++) {
          for (int x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) continue;
            vec2 sampleUv = vUv + vec2(float(x), float(y)) * texelSize;
            float sampleDepth = texture2D(depthBuffer, sampleUv).r;
            depthEdge = max(depthEdge, abs(sampleDepth - centerDepth));
            colorEdge = max(colorEdge, distance(base.rgb, texture2D(colorBuffer, sampleUv).rgb));
          }
        }
        float edge = max(
          smoothstep(depthThreshold, depthThreshold * 3.0, depthEdge),
          smoothstep(colorThreshold, colorThreshold * 1.6, colorEdge) * 0.72
        );
        gl_FragColor = vec4(mix(base.rgb, outlineColor, edge), base.a);
        #include <colorspace_fragment>
      }
    `,
    depthTest: false,
    depthWrite: false,
    blending: NoBlending,
    toneMapped: false,
  });
  const quadScene = new Scene();
  const quadCamera = new OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const quad = new Mesh(new PlaneGeometry(2, 2), material);
  quadScene.add(quad);

  let width = 1;
  let height = 1;
  const resize = (cssWidth, cssHeight) => {
    const pixelRatio = renderer.getPixelRatio();
    width = Math.max(1, Math.floor(cssWidth * pixelRatio));
    height = Math.max(1, Math.floor(cssHeight * pixelRatio));
    target.setSize(width, height);
    material.uniforms.texelSize.value.set(1 / width, 1 / height);
  };
  const render = (scene, camera) => {
    renderer.setRenderTarget(target);
    renderer.clear();
    renderer.render(scene, camera);
    renderer.setRenderTarget(null);
    renderer.render(quadScene, quadCamera);
  };
  const dispose = () => {
    target.dispose();
    material.dispose();
    quad.geometry.dispose();
  };
  return { resize, render, dispose };
}
