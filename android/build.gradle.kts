allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Align Kotlin and Java JVM targets to JDK 17 for all subprojects so that
    // third-party plugins (e.g. flutter_js which uses the legacy 'kotlin-android'
    // plugin and sets jvmTarget=1.8) do not hit the Kotlin 2.x JVM-target
    // validation error (Java=11, Kotlin=1.8 by default).
    afterEvaluate {
        if (plugins.hasPlugin("kotlin-android") ||
            plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>(
                "kotlin",
            ) {
                compilerOptions {
                    jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                }
            }
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension>(
            "android",
        ) {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
