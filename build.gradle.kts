plugins {
	application
	kotlin("jvm") version "1.4.31"

	id("com.github.johnrengelman.shadow") version "5.2.0"
}

repositories {
	jcenter()
	maven(url = "https://www.assemblogue.com/m2repository/")
}

java {
	sourceCompatibility = JavaVersion.VERSION_1_8
	targetCompatibility = JavaVersion.VERSION_1_8
}

application {
	mainClassName = "Client"
	defaultTasks("run")
}

dependencies {
	compileOnly(files("$projectDir/libs/plr2_util.jar"))
	implementation(kotlin("stdlib-jdk8"))
	implementation("com.fasterxml.jackson.core:jackson-databind:2.9.8")
	implementation("com.squareup.okhttp3:okhttp:4.9.0")
	implementation("org.apache.poi:poi:4.1.0")
	implementation("org.apache.poi:poi-ooxml:4.1.0")
	implementation("com.assemblogue.plr:lib-generic:2.2.+")
	testImplementation(platform("org.junit:junit-bom:5.7.1"))
	testImplementation("org.junit.jupiter:junit-jupiter")
	testImplementation("com.squareup.okhttp3:mockwebserver:4.9.0")
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
