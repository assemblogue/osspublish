// -*- coding: utf-8 -*-

import Client.Companion.convertUsingOnlineService
import Client.Companion.filesToUpload
import Client.Companion.findExportUrl
import Client.Companion.generateOssId
import Client.Companion.normalizeOssId
import Client.Companion.parseFileToUpload
import Client.Companion.hasEmptyContent
import Client.Companion.unzipInputStream
import com.fasterxml.jackson.databind.ObjectMapper
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import okio.source
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
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
		assertThrows(IllegalStateException::class.java) {
			parseFileToUpload("ontology", ObjectMapper().readTree("{}"), mapOf())
		}
		assertThrows(IllegalStateException::class.java) {
			parseFileToUpload("ontology", ObjectMapper().readTree("{\"id\": \"test\"}"), mapOf())
		}
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
	fun `0 byte is empty`() {
		assert(hasEmptyContent(FileToUpload("ontology", "foo_bar", mapOf(), content="")))
	}

	@Test
	fun `ontology with no definition is empty`() {
		assert(hasEmptyContent(FileToUpload("ontology", "foo_bar", mapOf(), content="""
{
	"@context" : "http://PUBLIC/ontologies/menuContext.jsonld",
	"@id" : "",
	"@type" : "PlrOntology",
	"defines" : [],
	"label" : {}
}
""")))
	}

	@Test
	fun `ontology with definition is not empty`() {
		assertFalse(hasEmptyContent(FileToUpload("ontology", "foo_bar", mapOf(), content="""
{
	"@context" : "http://PUBLIC/ontologies/menuContext.jsonld",
	"@id" : "",
	"@type" : "PlrOntology",
	"defines" : [{
		"@id": "Node",
		"@type": "Class",
		"subClassOf": [
			"Resource",
			"owl:Thing",
			"schema:Thing"
		],

		"label": {
			"": "Node",
			"ja": "ノード"
		}
	}],
	"label" : {}
}
""")))
	}

	@Test
	fun `stylesheet with no restriction is empty`() {
		assert(hasEmptyContent(FileToUpload("restriction", "foo_bar", mapOf(), content="""
{
	 "@context" : "http://PUBLIC/ontologies/menuContext.jsonld",
	 "restriction" : {
			"@id" : "Foo",
			"defines" : []
	 }
}
""")))
	}

	@Test
	fun `ill-formatted stylesheet raises exception`() {
		assertThrows(com.fasterxml.jackson.core.JsonParseException::class.java) {
			hasEmptyContent(FileToUpload("restriction", "foo_bar", mapOf(), content="{{"))
		}
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
	fun `unzip a large zip as stream`() {
		val stream = this.javaClass.classLoader.getResource("large.zip")!!.openStream()
		val pairs = unzipInputStream(stream)
		assertEquals(setOf("pg1.txt", "pg2.txt"), pairs.keys.toSet())
		assertEquals(listOf(120946, 11101), listOf(pairs["pg1.txt"]!!, pairs["pg2.txt"]!!).map{ it.toByteArray().size })
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
