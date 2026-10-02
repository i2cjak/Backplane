plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "dev.backplane.mobile"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.backplane.mobile"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // signed with the debug key until a release key exists
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    // bridge.js is copied in by scripts/build-mobile.sh
    sourceSets["main"].assets.srcDir("../../build/assets")
}

dependencies {
    val bom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(bom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("wang.harlon.quickjs:wrapper-android:3.2.3")
    implementation("androidx.javascriptengine:javascriptengine:1.0.0")
    // the pairing code scanner (Google Play services, no camera permission)
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    // it brings an old Fragment; the ActivityResult APIs need 1.3 or later
    implementation("androidx.fragment:fragment-ktx:1.8.5")
}
