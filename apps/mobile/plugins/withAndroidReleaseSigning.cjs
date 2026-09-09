const { withAppBuildGradle } = require("expo/config-plugins");

const SIGNING_ENVIRONMENT = {
  storeFile: "BACKPLANE_ANDROID_KEYSTORE_PATH",
  storePassword: "BACKPLANE_ANDROID_KEYSTORE_PASSWORD",
  keyAlias: "BACKPLANE_ANDROID_KEY_ALIAS",
  keyPassword: "BACKPLANE_ANDROID_KEY_PASSWORD",
};

module.exports = function withAndroidReleaseSigning(config) {
  return withAppBuildGradle(config, (nextConfig) => {
    const configured = Object.values(SIGNING_ENVIRONMENT).some((name) => process.env[name]);
    if (!configured) {
      return nextConfig;
    }
    const missing = Object.values(SIGNING_ENVIRONMENT).filter((name) => !process.env[name]);
    if (missing.length > 0) {
      throw new Error(`Incomplete Android release signing configuration: ${missing.join(", ")}`);
    }

    const contents = nextConfig.modResults.contents;
    const signingConfig = `    release {\n      storeFile file(System.getenv("${SIGNING_ENVIRONMENT.storeFile}"))\n      storeType "PKCS12"\n      storePassword System.getenv("${SIGNING_ENVIRONMENT.storePassword}")\n      keyAlias System.getenv("${SIGNING_ENVIRONMENT.keyAlias}")\n      keyPassword System.getenv("${SIGNING_ENVIRONMENT.keyPassword}")\n    }\n`;

    if (contents.includes('storeFile file(System.getenv("BACKPLANE_ANDROID_KEYSTORE_PATH"))')) {
      return nextConfig;
    }

    const withSigningConfig = contents.replace(
      "  buildTypes {",
      `  signingConfigs {\n${signingConfig}  }\n  buildTypes {`,
    );
    if (withSigningConfig === contents) {
      throw new Error("Could not find Android buildTypes block for release signing.");
    }

    const withReleaseSigning = withSigningConfig.replace(
      /(        release \{[\s\S]*?)            signingConfig signingConfigs\.debug/,
      "$1            signingConfig signingConfigs.release",
    );
    if (withReleaseSigning === withSigningConfig) {
      throw new Error("Could not replace Android release signing configuration.");
    }

    nextConfig.modResults.contents = withReleaseSigning;
    return nextConfig;
  });
};
