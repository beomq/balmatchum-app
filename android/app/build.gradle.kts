import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter passes --dart-define values as base64 "KEY=VALUE" items; native config reads the same values.
val dartDefines: Map<String, String> = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(',')
    .filter { it.isNotBlank() }
    .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    .associate { it.substringBefore('=') to it.substringAfter('=', "") }
val kakaoNativeAppKey = dartDefines["KAKAO_NATIVE_APP_KEY"].orEmpty()

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
        // Health Connect's stable client requires Android 8.0 (API 26).
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = providers.environmentVariable("ADMOB_ANDROID_APP_ID").orNull ?: ""
        manifestPlaceholders["kakaoScheme"] =
            if (kakaoNativeAppKey.isEmpty()) "com.beomq.balmatchum.kakao-unconfigured" else "kakao$kakaoNativeAppKey"
    }

    signingConfigs {
        create("devUpload") {
            storeType = "PKCS12"
            storeFile = providers.environmentVariable("BALMATCHUM_DEV_STORE_FILE").orNull?.let { file(it) }
            storePassword = providers.environmentVariable("BALMATCHUM_DEV_STORE_PASSWORD").orNull
            keyAlias = "balmatchum-dev-upload"
            keyPassword = providers.environmentVariable("BALMATCHUM_DEV_KEY_PASSWORD").orNull
        }
        create("prodUpload") {
            storeType = "PKCS12"
            storeFile = providers.environmentVariable("BALMATCHUM_PROD_STORE_FILE").orNull?.let { file(it) }
            storePassword = providers.environmentVariable("BALMATCHUM_PROD_STORE_PASSWORD").orNull
            keyAlias = "balmatchum-prod-upload"
            keyPassword = providers.environmentVariable("BALMATCHUM_PROD_KEY_PASSWORD").orNull
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            if (providers.environmentVariable("ADMOB_TEST_ADS").orNull == "true") {
                manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
            }
            resValue("string", "app_name", "발맞춤 Dev")
            signingConfig = signingConfigs.getByName("devUpload")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "발맞춤")
            signingConfig = signingConfigs.getByName("prodUpload")
        }
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

val validateProdSigning by tasks.registering {
    doLast {
        val required = listOf(
            "BALMATCHUM_PROD_STORE_FILE",
            "BALMATCHUM_PROD_STORE_PASSWORD",
            "BALMATCHUM_PROD_KEY_PASSWORD",
        )
        check(required.all { !providers.environmentVariable(it).orNull.isNullOrBlank() }) {
            "Prod release requires BALMATCHUM_PROD_STORE_FILE, BALMATCHUM_PROD_STORE_PASSWORD and BALMATCHUM_PROD_KEY_PASSWORD."
        }
        val store = file(providers.environmentVariable("BALMATCHUM_PROD_STORE_FILE").get())
        check(store.isAbsolute && store.isFile) { "Prod signing requires an existing keystore file." }
    }
}

tasks.matching { it.name == "preProdReleaseBuild" }.configureEach {
    dependsOn(validateProdSigning)
}

val validateProdReleaseAppConfig by tasks.registering {
    val defines = dartDefines
    doLast {
        val rules = mapOf(
            "SERVER_URL" to Regex("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~-]+)*/$"),
            "KAKAO_NATIVE_APP_KEY" to Regex("^[0-9a-f]{32}$"),
            "GOOGLE_SERVER_CLIENT_ID" to Regex("^[0-9]+-[a-z0-9]+\\.apps\\.googleusercontent\\.com$"),
        )
        val invalid = rules.filterNot { (name, rule) -> rule.matches(defines[name].orEmpty()) }.keys
        check(invalid.isEmpty()) {
            "Prod release requires --dart-define-from-file from tool/release_app_config.sh; " +
                "missing or malformed: ${invalid.joinToString()}."
        }
    }
}

tasks.matching { it.name == "preProdReleaseBuild" }.configureEach {
    dependsOn(validateProdReleaseAppConfig)
}

// Release variants must carry a real AdMob app ID; debug builds keep the empty default.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        val variantName = variant.name
        val taskSuffix = variantName.replaceFirstChar { it.uppercase() }
        val appId = variant.manifestPlaceholders.getting("admobAppId")
        val validate = tasks.register("validate${taskSuffix}AdmobAppId") {
            doLast {
                val id = appId.orNull.orEmpty()
                check(
                    Regex("^ca-app-pub-[0-9]{16}~[0-9]{10}$").matches(id) &&
                        !id.startsWith("ca-app-pub-3940256099942544~"),
                ) {
                    "$variantName requires a real ADMOB_ANDROID_APP_ID (ca-app-pub-<16 digits>~<10 digits>). " +
                        "Missing values and the Google sample app ID (ADMOB_TEST_ADS=true) are rejected."
                }
            }
        }
        tasks.matching { it.name == "pre${taskSuffix}Build" }.configureEach {
            dependsOn(validate)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.health.connect:connect-client:1.1.0")
    testImplementation("junit:junit:4.13.2")
}
