import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

repositories {
	gradlePluginPortal()
	maven(url = uri("https://www.assemblogue.com/m2repository/"))
	maven(url = uri("https://jitpack.io/")) // for com.github.kittinunf.result:result:2.2.0.
}

plugins {
	kotlin("jvm") version "2.2.20"
	id("com.gradleup.shadow") version "8.3.3"
	application
}

java {
	sourceCompatibility = JavaVersion.VERSION_1_8
	targetCompatibility = JavaVersion.VERSION_1_8

	toolchain {
		languageVersion = JavaLanguageVersion.of(21)
	}
}

application {
	mainClass ="Client"
	defaultTasks("run")
}

dependencies {
	//compileOnly(files("$projectDir/libs/plr2_util.jar"))
	implementation(kotlin("stdlib-jdk8"))
	implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
	implementation("com.fasterxml.jackson.core:jackson-databind:2.12.4")
	implementation("com.squareup.okhttp3:okhttp:4.9.1")
	implementation("org.apache.poi:poi:4.1.2")
	implementation("org.apache.poi:poi-ooxml:4.1.2")
	implementation("com.assemblogue.plr:lib-generic:2.2.+")
	testImplementation("org.junit.jupiter:junit-jupiter:5.7.2")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
	testRuntimeOnly("com.squareup.okhttp3:mockwebserver:4.9.1")
}

tasks {
	test {
		useJUnitPlatform()
		testLogging.showStandardStreams = true
		testLogging.events("PASSED", "FAILED", "SKIPPED", "STANDARD_OUT", "STANDARD_ERROR")
	}
}

kotlin {
	compilerOptions {
		jvmTarget.set(JvmTarget.JVM_1_8)
		languageVersion.set(KotlinVersion.KOTLIN_2_2)
		apiVersion.set(KotlinVersion.KOTLIN_2_2)
	}
}

tasks.named<KotlinCompile>("compileTestKotlin") {
	compilerOptions {
		suppressWarnings.set(true)
	}
}
