import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val remoteSigningOption = providers.gradleProperty("bnbuRemoteSigning").orNull
require(remoteSigningOption == null || remoteSigningOption in listOf("true", "false")) {
    "bnbuRemoteSigning must be true or false."
}
// This explicit staging lane produces an unsigned APK for the private signer.
val usesRemoteSigning = remoteSigningOption == "true"
val hasReleaseSigning = keystorePropertiesFile.exists() && !usesRemoteSigning
if (hasReleaseSigning) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

gradle.taskGraph.whenReady {
    val releasePackagingTaskPrefixes = listOf(
        "assemble",
        "bundle",
        "package",
        "sign",
        "validateSigning",
    )
    val schedulesReleasePackaging = allTasks.any { task ->
        task.project == project &&
            task.name.contains("release", ignoreCase = true) &&
            releasePackagingTaskPrefixes.any { prefix ->
                task.name.startsWith(prefix, ignoreCase = true)
            }
    }
    if (usesRemoteSigning && allTasks.any { task ->
            task.project == project && task.name.startsWith("bundle", ignoreCase = true)
        }) {
        throw GradleException("Remote signing supports APK staging only, not App Bundles.")
    }
    if (schedulesReleasePackaging && !hasReleaseSigning && !usesRemoteSigning) {
        throw GradleException(
            "Release signing is not configured. Copy key.properties.example to " +
                "android/key.properties and provide an upload keystore, or use the " +
                "documented bnbuRemoteSigning APK staging lane."
        )
    }
}

android {
    namespace = "me.bnbu.app"
    compileSdk = 36
    ndkVersion = "27.2.12479018"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "me.bnbu.app"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("androidx.webkit:webkit:1.17.0")
}

flutter {
    source = "../.."
}
