// android/build.gradle.kts

buildscript {
    // --- AQUI ESTÁ A CORREÇÃO DO KOTLIN ---
    val kotlin_version by extra("2.1.0") 
    
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Verifique se a versão do Gradle agp bate com a sua, geralmente é 7.3.0 ou superior
        // Se der erro, tente mudar para "8.1.0" ou mantenha a que estava se você souber
        classpath("com.android.tools.build:gradle:7.3.0")
        
        // Plugin do Kotlin com a versão nova
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
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