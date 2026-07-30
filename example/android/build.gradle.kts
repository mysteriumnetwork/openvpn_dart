allprojects {
    repositories {
        google()
        mavenCentral()
        // Local Maven repo (in the openvpn_dart plugin) holding the ics-openvpn AAR built
        // from source. Path is relative to this example's android/ dir → ../../android/localmaven.
        // Real consumers add the equivalent repo until the AAR is published to a shared Maven.
        maven { url = uri("${rootProject.projectDir}/../../android/localmaven") }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
