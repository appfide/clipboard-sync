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
}

// Several Flutter plugins still declare compileSdk 33; androidx libraries
// pulled in by flutter_secure_storage need ≥34. Align every library module
// with the app's compileSdk so AAR metadata checks pass. Registered before
// evaluationDependsOn(":app") so no subproject has been evaluated yet.
val alignedCompileSdk = 37
subprojects {
    if (!project.state.executed) {
        afterEvaluate {
            extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.apply {
                if ((compileSdk ?: 0) < alignedCompileSdk) compileSdk = alignedCompileSdk
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
