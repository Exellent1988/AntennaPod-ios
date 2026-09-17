plugins {
    kotlin("multiplatform") version "2.3.20"
}

group = "de.danoeh.antennapod"
version = "0.1.0-SNAPSHOT"

kotlin {
    jvm()

    listOf(
        iosX64(),
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach { target ->
        target.binaries.framework {
            baseName = "AntennaPodShared"
            isStatic = true
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation("com.fleeksoft.ksoup:ksoup:0.2.6")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
