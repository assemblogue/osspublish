import com.assemblogue.plr.lib.PLR
import java.io.FileReader
import java.io.File
import java.util.zip.ZipFile
import java.util.Properties

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.JsonNode

data class FileToUpload (val linkName: String, val labels: Map<String, String>,
                         val format:String="application/ld+json", val content:String="")

class Client {

    companion object {

        fun unzipFile(file: File): Map<String, String> {
            return ZipFile(file).use { zip ->
                zip.entries().asSequence().associate { entry ->
                    Pair(entry.name, zip.getInputStream(entry).use { input ->
                        input.bufferedReader().use { it.readText() }
                    })
                }
            }
        }

        fun parseLabels(node: JsonNode): Map<String, String> {
            return node.fields().asSequence().associate{ x -> Pair(x.key, x.value.asText())}
        }

        fun parseFileToUpload(linkName: String, node: JsonNode, fileEntries: Map<String, String>): FileToUpload {
            val format = node.get("format").asText()
            val file = node.get("file").asText()
            val labels = parseLabels(node.get("label")!!)
            return FileToUpload(linkName, labels, format, fileEntries[file!!]!!)
        }

        fun parseIndexJson(node: JsonNode, fileEntries: Map<String, String>): List<FileToUpload> {
            return  arrayOf("ontology", "restriction").flatMap { linkName ->
                node.get(linkName).let { n -> (0 until n.size()).map {
                    parseFileToUpload(linkName, n.get(it), fileEntries)
                } }
            }
        }

        @JvmStatic
        fun main(args: Array<String>) {
            val plr = (PLR.createBuilder() as com.assemblogue.plr.lib.generic.PlrBuilder).build()
            val props = Properties()
            props.load(FileReader("config.properties"))

            val entries = unzipFile(File(args[0]))
            println(parseIndexJson(ObjectMapper().readTree(entries["index.json"] as String), entries))

            val plrId = props.getProperty("plr.id")
            val (storageId, userId) = plrId.split(":", limit = 2).let{ a -> Pair(a[0], a[1])}
            //val passphrase = props.getProperty("plr.passphrase", "")
            val storageInfo = plr.listStorages().filter {
                x -> x.typeName == storageId && x.userId == userId
            }[0]
            val storage = plr.connectStorage(storageInfo)

            val root = plr.getPublicRoot(storage)
            root.syncAndWait()
            println(root.allProperties)

        }
    }
}
