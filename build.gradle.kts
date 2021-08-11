repositories {
	gradlePluginPortal()
	maven(url = "https://www.assemblogue.com/m2repository/")
}

plugins {
	kotlin("jvm") version "1.5.20"
	id("com.github.johnrengelman.shadow") version "6.1.0"
	application
}

java {
	sourceCompatibility = JavaVersion.VERSION_1_8
	targetCompatibility = JavaVersion.VERSION_1_8
}

application {
	mainClassName ="Client"
	defaultTasks("run")
}

dependencies {
	compileOnly(files("$projectDir/libs/plr2_util.jar"))
	implementation(kotlin("stdlib-jdk8"))
	implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.5.0")
	implementation("com.fasterxml.jackson.core:jackson-databind:2.12.4")
	implementation("com.squareup.okhttp3:okhttp:4.9.1")
	implementation("org.apache.poi:poi:4.1.2")
	implementation("org.apache.poi:poi-ooxml:4.1.2")
	implementation("com.assemblogue.plr:lib-generic:2.2.+")
	testImplementation("org.junit.jupiter:junit-jupiter:5.7.2")
	testImplementation("com.squareup.okhttp3:mockwebserver:4.9.1")
}

tasks {
	test {
		useJUnitPlatform()
		testLogging.showStandardStreams = true
		testLogging.events("PASSED", "FAILED", "SKIPPED", "STANDARD_OUT", "STANDARD_ERROR")
	}

	compileKotlin {
		kotlinOptions.jvmTarget = "1.8"
	}

	compileTestKotlin {
		kotlinOptions.jvmTarget = "1.8"
		kotlinOptions.suppressWarnings = false
	}
}
