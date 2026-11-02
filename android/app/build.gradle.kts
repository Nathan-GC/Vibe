import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature release : clé d'upload lue dans android/key.properties (jamais
// versionné, voir .gitignore) : storePassword, keyPassword, keyAlias et storeFile
// (chemin relatif à android/app). Absent (poste de dev, tests) : repli sur la clé
// debug, signalé par un avertissement — un tel build est refusé par Google Play.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

// Build Google Play (`flutter build apk --dart-define=PLAY_STORE=true`, voir
// AppConstants.playStoreBuild) : Play interdit REQUEST_INSTALL_PACKAGES pour
// une auto-mise à jour hors Play Store. Ce build utilise une copie du manifeste
// où la permission est marquée tools:node="remove" (retirée aussi si une
// bibliothèque la déclare) — voir la fin du bloc `android` ci-dessous. Le build
// par défaut reste inchangé. Flutter passe les --dart-define à Gradle en
// base64 dans la propriété "dart-defines". (`Base64` importé : dans un script
// Gradle, `java.` désigne l'extension `java` du projet, pas le paquet.)
val playStoreBuild = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.any { String(Base64.getDecoder().decode(it)) == "PLAY_STORE=true" } == true

android {
    namespace = "com.vibeplayer.app"
    // permission_handler_android exige compileSdk >= 37 (voir checkDebugAarMetadata) ;
    // flutter.compileSdkVersion (36) est insuffisant.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requis par flutter_local_notifications (java.time / API 26+ desugarées).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.vibeplayer.app"
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
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("android/key.properties absent : build release signé avec la clé debug.")
                signingConfigs.getByName("debug")
            }
        }
    }

    // Build Google Play : voir `playStoreBuild` en tête de fichier.
    // READ_MEDIA_IMAGES/READ_MEDIA_VIDEO : fusionnées depuis open_filex, qui ne
    // sert qu'à la mise à jour APK (masquée dans ce build) et ne sont jamais
    // demandées à l'exécution (pochettes/vidéos : sélecteur photo d'Android,
    // sans permission) — politique Play sur les photos et vidéos.
    if (playStoreBuild) {
        val installPermission = "<uses-permission android:name=\"android.permission.REQUEST_INSTALL_PACKAGES\"/>"
        val source = file("src/main/AndroidManifest.xml").readText()
        check(installPermission in source) { "REQUEST_INSTALL_PACKAGES introuvable dans le manifeste : mettre à jour ce bloc." }
        val removed = listOf("REQUEST_INSTALL_PACKAGES", "READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO")
            .joinToString("\n    ") { "<uses-permission android:name=\"android.permission.$it\" tools:node=\"remove\"/>" }
        val playManifest = layout.buildDirectory.file("play-store/AndroidManifest.xml").get().asFile
        playManifest.parentFile.mkdirs()
        playManifest.writeText(source.replace(installPermission, removed))
        sourceSets.getByName("main").manifest.srcFile(playManifest)
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
