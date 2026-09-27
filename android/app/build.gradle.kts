plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.beomq.balmatchum"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.beomq.balmatchum"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("devUpload") {
            storeType = "PKCS12"
            storeFile = providers.environmentVariable("BALMATCHUM_DEV_STORE_FILE").orNull?.let { file(it) }
            storePassword = providers.environmentVariable("BALMATCHUM_DEV_STORE_PASSWORD").orNull
            keyAlias = "balmatchum-dev-upload"
            keyPassword = providers.environmentVariable("BALMATCHUM_DEV_KEY_PASSWORD").orNull
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "발맞춤 Dev")
            signingConfig = signingConfigs.getByName("devUpload")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "발맞춤")
        }
    }
}

// Production release needs a separately approved key/configuration. Never use the Dev key.
androidComponents {
    beforeVariants(selector().withFlavor("environment" to "prod").withBuildType("release")) {
        it.enable = false
    }
}

val validateDevSigning by tasks.registering {
    doLast {
        val required = listOf(
            "BALMATCHUM_DEV_STORE_FILE",
            "BALMATCHUM_DEV_STORE_PASSWORD",
            "BALMATCHUM_DEV_KEY_PASSWORD",
        )
        check(required.all { !providers.environmentVariable(it).orNull.isNullOrBlank() }) {
            "Dev release requires BALMATCHUM_DEV_STORE_FILE, BALMATCHUM_DEV_STORE_PASSWORD and BALMATCHUM_DEV_KEY_PASSWORD."
        }
        val store = file(providers.environmentVariable("BALMATCHUM_DEV_STORE_FILE").get())
        check(store.isAbsolute && store.isFile) { "Dev signing requires an existing keystore file." }
    }
}

tasks.matching { it.name == "preDevReleaseBuild" }.configureEach {
    dependsOn(validateDevSigning)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
