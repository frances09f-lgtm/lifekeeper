import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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
subprojects {
    // Plugins such as file_picker declare Java 11 but leave Kotlin on its default.
    // Make each Kotlin task use the target of the Java task in the same module.
    tasks.withType<KotlinCompile>().configureEach {
        val kotlinTaskName = name
        val owner = project
        compilerOptions.jvmTarget.set(
            owner.provider {
                val javaTask = owner.tasks.findByName(kotlinTaskName.replace("Kotlin", "JavaWithJavac")) as? JavaCompile
                JvmTarget.fromTarget(javaTask?.targetCompatibility ?: "17")
            }
        )
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
