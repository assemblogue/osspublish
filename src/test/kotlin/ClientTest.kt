// -*- coding: utf-8 -*-

import Client.Companion.authenticateAndGetStorage
import Client.Companion.conversionFailures
import Client.Companion.conversionWarnings
import Client.Companion.convertUsingOnlineService
import Client.Companion.filesToUpload
import Client.Companion.findExportUrl
import Client.Companion.findOntologyName
import Client.Companion.generateOssId
import Client.Companion.normalizeOssId
import Client.Companion.parseFileToUpload
import Client.Companion.hasEmptyContent
import Client.Companion.requireSuccessfulConversion
import Client.Companion.unzipInputStream
import com.assemblogue.plr.io.Storage
import com.assemblogue.plr.io.StorageInfo
import com.assemblogue.plr.lib.PLR
import com.fasterxml.jackson.databind.ObjectMapper
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import okio.source
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.apache.poi.xssf.usermodel.XSSFWorkbook
import org.mockito.kotlin.*
import java.io.ByteArrayOutputStream
import java.net.URL

class ClientTest {
	private fun resource(name: String): URL =
		requireNotNull(this.javaClass.getResource("/$name")) { "resource $name is missing" }

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
		resource("test_dummy.zip").openStream().use { stream ->
			assertEquals("{}", unzipInputStream(stream)["index.json"]!!.trim())
			assertThrows(java.io.IOException::class.java) {
				stream.available()
			}
		}
	}

	@Test
	fun `unzip a large zip as stream`() {
		val stream = resource("large.zip").openStream()
		val pairs = unzipInputStream(stream)
		assertEquals(setOf("pg1.txt", "pg2.txt"), pairs.keys.toSet())
		assertEquals(listOf(120946, 11101), listOf(pairs["pg1.txt"]!!, pairs["pg2.txt"]!!).map{ it.toByteArray().size })
	}

	@Test
	fun `parses a dummy zip and get an empty index`() {
		val buffer = Buffer()
		buffer.writeAll(resource("test_dummy.zip").openStream().source())
		val server = MockWebServer()
		server.enqueue(MockResponse().setBody(buffer))
		server.start()
		val entries = convertUsingOnlineService("".toByteArray(), "testData", server.url("/convert/"))
		assertEquals("{}", entries["index.json"]!!.trim())
		server.shutdown()
	}

	@Test
	fun `forceAuthentication true calls newStorage even if storage exists`() {
		val plr = mock<PLR>()
		val storageinfo = mock<StorageInfo>()
		val storage = mock<Storage>()

		whenever(storageinfo.typeName).thenReturn("googleDrive")
		whenever(storageinfo.userId).thenReturn("foobar@gmail.com")
		whenever(plr.listStorages()).thenReturn(listOf(storageinfo))
		whenever(plr.newStorage(any())).thenReturn(storage)

		// when
		val result = authenticateAndGetStorage(
				plr = plr,
				plrId = "googleDrive:foobar@gmail.com",
				passphrase = "barbar",
				forceAuthentication = true
		)

		// then
		verify(plr).newStorage(any())
		verify(plr, never()).connectStorage(any())
		assert(result == storage)
	}

	@Test
	fun `conversionFailures lists failures of every file`() {
		val node = ObjectMapper().readTree("""
		{
		  "response": [
		    {"file": "bad1.csv", "error": [{"command": "perl cto.pl", "message": "syntax error"}]},
		    {"file": "good.csv", "error": []},
		    {"file": "bad2.xlsx", "error": [{"message": "Zip::Error: broken"}]}
		  ]
		}
		""".trimIndent())

		assertEquals(
			listOf("bad1.csv: syntax error", "bad2.xlsx: Zip::Error: broken"),
			conversionFailures(node))
	}

	@Test
	fun `conversionFailures is empty when nothing failed`() {
		assertEquals(listOf<String>(), conversionFailures(ObjectMapper().readTree("{}")))
		assertEquals(
			listOf<String>(),
			conversionFailures(ObjectMapper().readTree("""{"response": [{"file": "a.csv", "error": []}]}""")))
	}

	@Test
	fun `conversionFailures tolerates a missing or null error field`() {
		val node = ObjectMapper().readTree("""
		{"response": [
		  {"file": "no_error_field.csv"},
		  {"file": "null_error.csv", "error": null},
		  {"file": "bad.csv", "error": [{"message": "boom"}]}
		]}
		""".trimIndent())

		assertEquals(listOf("bad.csv: boom"), conversionFailures(node))
	}

	@Test
	fun `conversionWarnings lists the warnings line by line with the file name`() {
		val node = ObjectMapper().readTree("""
		{
		  "response": [
		    {"file": "a.csv", "error": [], "warning": [
		      {"command": "perl cto.pl", "exit_status": 0, "message": "Warning: one\nWarning: two\n"}
		    ]},
		    {"file": "clean.csv", "error": [], "warning": []},
		    {"file": "old_server.csv", "error": []},
		    {"file": "null_warning.csv", "warning": null}
		  ]
		}
		""".trimIndent())

		assertEquals(listOf("a.csv: Warning: one", "a.csv: Warning: two"), conversionWarnings(node))
		assertEquals(listOf<String>(), conversionFailures(node))
	}

	@Test
	fun `conversionWarnings is empty when there is no response`() {
		assertEquals(listOf<String>(), conversionWarnings(ObjectMapper().readTree("{}")))
	}

	@Test
	fun `conversion error message does not include the command`() {
		val node = ObjectMapper().readTree("""
		{"response": [{"file": "x.csv", "error": [
		  {"command": "perl plrv2/contentsdata/cto/cto.pl /tmp/x", "exit_status": 255, "message": "Error: no value for `| count' at line 3"}
		]}]}
		""".trimIndent())

		val ex = assertThrows(ClientException::class.java) { requireSuccessfulConversion(node) }

		assertEquals("Conversion failed:\nx.csv: Error: no value for `| count' at line 3", ex.message)
	}

	@Test
	fun `requireSuccessfulConversion reports conversion error`() {
		val node = ObjectMapper().readTree("""
		{
		  "response": [
		    {
		      "file": "input_with_error.csv",
		      "error": [
		        {
		          "command": "perl plrv2/contentsdata/cto/cto.pl /tmp/x",
							"exit_status": 255,
		          "message": "Error: no value for `| count' at line 3"
		        }
		      ]
		    }
		  ]
		}
	""".trimIndent())

		val ex = assertThrows(ClientException::class.java) {
			requireSuccessfulConversion(node)
		}

		assertTrue(ex.message!!.contains("input_with_error.csv: Error: no value for"))
	}

	@Test
	fun `findOntologyName fails for an empty file`() {
		assertThrows(Exception::class.java) {
			findOntologyName("".toByteArray()).getOrThrow()
		}
	}

	/** Builds an xlsx whose first cell (A1) holds [a1]. */
	private fun xlsxWithFirstCell(a1: String): ByteArray {
		val out = ByteArrayOutputStream()
		XSSFWorkbook().use { wb ->
			wb.createSheet().createRow(0).createCell(0).setCellValue(a1)
			wb.write(out)
		}
		return out.toByteArray()
	}

	@Test
	fun `findOntologyName finds the ontology name in the first cell`() {
		val bytes = xlsxWithFirstCell("]O DG ja:談話グラフ;Discourse Graph")

		assertEquals("DG", findOntologyName(bytes).getOrThrow())
	}

	@Test
	fun `findOntologyName fails when the first cell of an xlsx is empty`() {
		val bytes = resource("empty.xlsx").readBytes()

		val ex = assertThrows(ClientException::class.java) {
			findOntologyName(bytes).getOrThrow()
		}

		assertEquals("Ontology name not found in the first cell: (empty)", ex.message)
	}
}
