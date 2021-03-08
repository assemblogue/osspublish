// -*- coding: utf-8 -*-

import Client.Companion.convertUsingOnlineService
import Client.Companion.filesToUpload
import Client.Companion.findExportUrl
import Client.Companion.generateOssId
import Client.Companion.normalizeOssId
import Client.Companion.parseFileToUpload
import Client.Companion.unzipInputStream
import com.fasterxml.jackson.databind.ObjectMapper
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import okio.source
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class ClientTest {
	@Test
	fun testParseFileToUpload() {
		val f = parseFileToUpload("ontology", ObjectMapper().readTree("""
						{
							"file": "f1.jsonld",
							"id": "Foo",
							"label": {
								"": "Foo1",
								"ja": "Bar2"
							},
							"format": "application/ld+json"
						}
						""".trimIndent()), hashMapOf("f1.jsonld" to "{\"foo\": 0}", "f2.jsonld" to "bar"))
		assertEquals(
			FileToUpload(
				"ontology",
				"Foo",
				hashMapOf("" to "Foo1", "ja" to "Bar2"),
				"application/ld+json",
				"{\"foo\": 0}"),
			f)
	}

	@Test
	fun testFilesToUpload() {
		val ls = filesToUpload(ObjectMapper().readTree("""
						{"ontology": [{
							"file": "f1.jsonld",
							"label": {
								"": "Foo1",
								"ja": "Bar2"
							},
							"id": "Foo",
							"format": "application/ld+json"
						}], "channelSS": [{
							"file": "f2.jsonld",
							"label": {
								"": "Foo3",
								"ja": "Bar4"
							},
							"id": "Foo",
							"format": "application/ld+json"
						}]}
						""".trimIndent()), hashMapOf("f1.jsonld" to "{\"foo\": 0}", "f2.jsonld" to "bar"))

		assertEquals(listOf(
			FileToUpload(
				"ontology",
				"Foo",
				hashMapOf("" to "Foo1", "ja" to "Bar2"),
				"application/ld+json",
				"{\"foo\": 0}"
			),
			FileToUpload(
				"channelSS",
				"Foo",
				hashMapOf("" to "Foo3", "ja" to "Bar4"),
				"application/ld+json",
				"bar")).toSet(),
			ls.toSet())
	}

	@Test
	fun testSha256() {
		assertEquals(
			"c3ab8ff13720e8ad9047dd39466b3c8974e592c2fa383d4a3960714caef0c4f2",
			Hasher().sha256("foobar"))
	}

	@Test
	fun `generate ossId from ja and default labels`() {
		assertEquals(
			"plr@assemblogue.com#bebf864fe47cca82#Base_ontology",
			generateOssId("ontology", hashMapOf("" to "Base!", "ja" to "基本!"), "Base", "plr@assemblogue.com"))
	}

	@Test
	fun `generate ossId from ja, zh and default labels`() {
		assertEquals(
			"plr@assemblogue.com#bebf864fe47cca82#Base_ontology",
			generateOssId("ontology", hashMapOf("" to "Base!", "ja" to "基本!", "zh" to "基本"), "Base", "plr@assemblogue.com"))
	}

	@Test
	fun `normalize ossId`() {
		assertEquals(
			"plr@assemblogue.com#bebf864fe47cca82",
			normalizeOssId("plr@assemblogue.com#bebf864fe47cca82#Base_ontology"))
	}

	@Test
	fun `normalize Google spreadsheet export url`() {
		assertEquals(
			"https://docs.google.com/spreadsheets/d/1xxxx_1xxxx/export",
			findExportUrl("https://docs.google.com/spreadsheets/d/1xxxx_1xxxx/edit"))
	}

	@Test
	fun `normalize Google spreadsheet export url with parameter`() {
		assertEquals(
			"https://docs.google.com/spreadsheets/d/1xxxx_1xxxx/export",
			findExportUrl("https://docs.google.com/spreadsheets/d/1xxxx_1xxxx/edit?usp=drive_web"))
	}

	@Test
	fun `open a dummy zip and ensure the stream is closed after`() {
		this.javaClass.classLoader.getResource("test_dummy.zip")!!.openStream().use { stream ->
		  assertEquals("{}", unzipInputStream(stream)["index.json"]!!.trim())
			assertThrows(java.io.IOException::class.java) {
				stream.available()
			}
		}
	}

	@Test
	fun `parses a dummy zip and get an empty index`() {
		val buffer = Buffer()
		buffer.writeAll(this.javaClass.classLoader.getResource("test_dummy.zip")!!.openStream().source())
		val server = MockWebServer()
		server.enqueue(MockResponse().setBody(buffer))
		server.start()
		val entries = convertUsingOnlineService("".toByteArray(), "testData", server.url("/convert/").toUrl())
		assertEquals("{}", entries["index.json"]!!.trim())
		server.shutdown()
	}
}
