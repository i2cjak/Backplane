import type { VercelConfig } from "@vercel/config/v1";

export const config: VercelConfig = {
  git: {
    deploymentEnabled: false,
  },
  installCommand: "npm install -g vite-plus && vp install --filter '@backplane/marketing...'",
  buildCommand: "vp run --filter @backplane/marketing build",
  outputDirectory: "dist",
};
