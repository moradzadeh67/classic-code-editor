allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Some plugins (for example file_picker 8.x) pin their own compileSdk below Android API 36,
// which fails the AAR metadata check against flutter_plugin_android_lifecycle. Force every
// Android subproject to compile against API 36 regardless of what it declares.
// This block must come before any subproject is evaluated, so it is declared first.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        val compileSdkSetter = androidExtension.javaClass.methods.firstOrNull { method ->
            method.parameterTypes.size == 1 &&
                (method.name == "setCompileSdkVersion" || method.name == "setCompileSdk")
        }
        compileSdkSetter?.invoke(androidExtension, 36)
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
