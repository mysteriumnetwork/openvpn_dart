allprojects {
    repositories {
        google()
        mavenCentral()
        
        // GitHub Maven for ics-openvpn/de.blinkt library
        maven {
            url = uri("https://raw.githubusercontent.com/schwabe/ics-openvpn/master/build-tools/maven/")
            name = "ics-openvpn-maven"
        }
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
