// Native half of the payriff Flutter plugin (CONTRACT §16.11): card encryption,
// X-Client-App-Id, FLAG_SECURE screen protection, hardened external launches, the
// removal of 3-D Secure website data (§9.1a), the root, hooking and debugger checks
// (§16.16) and Google Pay (§17.5). Its one third-party runtime dependency is Google's
// play-services-wallet, for the Google Pay API and its PayButton.
group = "com.payriff.flutter"
version = "1.0.0-rc.7"

buildscript {
    // CONTRACT §18.9: the lowest Kotlin Gradle plugin that builds the plugin, so it never pushes a
    // newer one onto the app. 2.2.10 is also the version AGP 9.1.0 below depends on, so this
    // classpath cannot resolve lower; the app's own Kotlin Gradle plugin (2.2.20 or newer for
    // Flutter 3.47) is the one that compiles the plugin.
    val kotlinVersion = "2.2.10"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.payriff.flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            all {
                it.outputs.upToDateWhen { false }
                it.testLogging {
                    events("passed", "skipped", "failed")
                    showExceptions = true
                    exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // CONTRACT §17.5. 19.5.0 rather than the newest, so the plugin never raises the version an
    // app or another plugin uses; the code also works with 20.x.
    implementation("com.google.android.gms:play-services-wallet:19.5.0")
    testImplementation("junit:junit:4.13.2")
}
