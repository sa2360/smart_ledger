allprojects {
    repositories {
        // Flutter 引擎构件国内镜像（显式声明，不依赖 FLUTTER_STORAGE_BASE_URL 环境变量）
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
        // 国内镜像优先，google()/mavenCentral() 兜底
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
