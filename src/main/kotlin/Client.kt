import com.assemblogue.plr.io.Storage
import com.assemblogue.plr.lib.EntityNode
import com.assemblogue.plr.lib.FileNode
import com.assemblogue.plr.lib.PLR
import com.assemblogue.plr.lib.model.PublicRoot
import com.assemblogue.plr.util.NodeSchemas
import java.io.FileReader
import java.io.File
import java.util.zip.ZipFile
import java.time.Instant

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.JsonNode
import okhttp3.*
import java.io.FileWriter
import java.lang.NumberFormatException
import java.net.URL
import java.security.MessageDigest
import java.text.MessageFormat
import java.util.*

data class FileToUpload (val linkName: String, val labels: Map<String, String>,
                         val format:String="application/ld+json", val content:String="")

data class FileInStorage (val linkName: String, val labels: Map<String, String>,
                          val format:String, val node: FileNode)

class Hasher {
    private val md = MessageDigest.getInstance("SHA-256")
    fun sha256(str: String): String {
        val digest = md.digest(str.toByteArray())
        return digest.fold("", { s, it -> s + "%02x".format(it) })
    }
}

class Res {
    private val formatter = MessageFormat("")
    fun format(messageId: String, vararg args: Any): String {
        formatter.applyPattern(ResourceBundle.getBundle("messages").getString(messageId))
        return formatter.format(args)
    }
}

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
            return node.fields().asSequence().associate{ Pair(it.key, it.value.asText())}
        }

        fun parseFileToUpload(linkName: String, node: JsonNode, fileEntries: Map<String, String>): FileToUpload {
            val format = node.get("format").asText()
            val file = node.get("file").asText()
            val labels = parseLabels(node.get("label")!!)
            return FileToUpload(linkName, labels, format,
                    fileEntries[file!!] ?: error("referencing non-existing file"))
        }

        fun filesToUpload(node: JsonNode, fileEntries: Map<String, String>): List<FileToUpload> {
            return  arrayOf("ontology", "restriction").flatMap { linkName ->
                if (node.has(linkName)) {
                node.get(linkName).let { n -> (0 until n.size()).map {
                    parseFileToUpload(linkName, n.get(it), fileEntries)
                } } } else {
                    listOf()
                }
            }
        }

        fun getPropOssOrCreate(root: PublicRoot): EntityNode {
            return if (root.propertyNames().contains(NodeSchemas.PROP_OSS)) {
                root.getProperty(NodeSchemas.PROP_OSS)[0].asEntity()
            } else {
                root.node.newEntity(
                        NodeSchemas.PROP_OSS,
                        NodeSchemas.CLASS_OSS,
                        false,
                        true).also {
                    it.syncAndWait()
                }
            }
        }

        fun filesInStorage(node: EntityNode): List<FileInStorage> {
            return NodeSchemas.PROP_OSS_CONTAINERS.flatMap { linkName ->
                node.getProperty(linkName).map{it.asFile()}.map { fn ->
                    val labels = fn.titleValueMap.map{ (k, v) -> (k!! to v!! as String)}.toMap()
                    FileInStorage(linkName, labels, fn.format, fn)
                }
            }
        }

        fun authenticateAndGetStorage(plr: PLR, plrId: String): Storage {
            val (storageType, userId) = try {
                plrId.split(":", limit = 2).let{ a -> Pair(a[0], a[1])}
            } catch (e: IndexOutOfBoundsException) {
                error("invalid user id $plrId; use this format: googleDrive:foobar@gmail.com")
            }
            val storages = plr.listStorages().filter {
                x -> x.typeName == storageType && x.userId == userId
            }
            return if (storages.isNotEmpty()) {
                plr.connectStorage(storages[0])
            } else {
                plr.newStorage(Storage.Type.byName(storageType))
            }
        }

        fun generateOssId(linkName: String, labels: Map<String, String>, baseName: String, userId: String): String {
            val key = arrayOf('"'+ linkName+'"',
                    labels.map{ (k, v) -> "[\"$k\", \"$v\"]"}
            ).joinToString(", ", "[", "]")
            return "$userId#" + Hasher().sha256(key).substring(0..15) + "#${baseName}_$linkName"
        }

        fun generateOssId(file: FileInStorage): String {
            return file.node.peerEntity.getProperty(NodeSchemas.PROP_OSS_ID)[0].asLiteral().value.toString()
        }
        fun generateOssId(file: FileToUpload, userId: String): String {
            return generateOssId(file.linkName, file.labels, file.labels[""]?:"", userId)
        }

        fun convertUsingOnlineService(spreadsheet: File, endpoint: URL): Map<String, String> {
            val client = OkHttpClient()
            val requestBody = MultipartBody.Builder().setType(MultipartBody.FORM)
                    .addFormDataPart(
                        "file", spreadsheet.name,
                        RequestBody.create(MediaType.parse("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"), spreadsheet))
                    .build()
            val request = Request.Builder()
                    .url(endpoint)
                    .post(requestBody)
                    .build()
            val response = client.newCall(request).execute()
            val bytes = response.body()!!.byteStream().readBytes()
            val file = createTempFile("oss", ".zip")
            file.writeBytes(bytes)
            System.err.println("temp file: $file")
            return unzipFile(file)
        }

        fun listFilesInStorage(ossNode: EntityNode): Sequence<String> {
            return filesInStorage(ossNode).asSequence().map { file ->
                val (ver, date) = file.node.entry.let {
                    Pair(it.listRevisions().size, Instant.ofEpochMilli(it.meta.lastModified()))
                }
                "${file.linkName} v$ver $date ${generateOssId(file)} ${file.labels}"
            }
        }

        fun findConfigOrCreate(file: File, defaults: Map<String, String>): Properties {
            return if (file.exists()) {
                Properties().also{ it.load(FileReader(file)) }
            } else {
                Properties().also { props ->
                    defaults.forEach{ (k, v) ->
                        props.setProperty(k, v)
                    }
                    props.store(FileWriter(file), "Configuration for $Client")
                }
            }
        }

        private fun putNewFileToStorage(ossNode: EntityNode, file: FileToUpload, id: String) {
            val fileNode = ossNode.newFile(file.linkName, file.format,true)
            fileNode.put(file.content.toByteArray())
            fileNode.titleValueMap = file.labels
            fileNode.peerEntity.newLiteral(NodeSchemas.PROP_OSS_ID).value = id
        }

        @JvmStatic
        fun main(args: Array<String>) {
            val plr = (PLR.createBuilder() as com.assemblogue.plr.lib.generic.PlrBuilder).build()!!
            val props = findConfigOrCreate(
                    File("config.properties"),
                    mapOf("plr.oss.endpoint" to "https://osscon.herokuapp.com/convert")
            )
            val plrId = props.getProperty("plr.id") ?: selectIdFromStorageList(plr)

            try {
                val storage = authenticateAndGetStorage(plr, plrId)
                val root = plr.getPublicRoot(storage)
                root.syncAndWait()
                val ossNode = getPropOssOrCreate(root)

                if (args.isNotEmpty()) {
                    val fileEntries = if (args[0].endsWith(".xlsx")) {
                        convertUsingOnlineService(File(args[0]), URL(props.getProperty("plr.oss.endpoint")))
                    } else {
                        unzipFile(File(args[0]))
                    }
                    val filesToUpload = filesToUpload(
                            ObjectMapper().readTree(fileEntries["index.json"] as String), fileEntries
                    ).associate { Pair(generateOssId(it, storage.userId), it) }
                    val filesInStorage = filesInStorage(ossNode).associate { x -> Pair(generateOssId(x), x) }
                    filesToUpload.forEach { (id, file) ->
                        if (filesInStorage.contains(id)) {
                            println("Overwriting ${file.labels}: $id")
                            filesInStorage.getValue(id).node.let { n ->
                                println(n.id)
                                n.put(file.content.toByteArray())
                                n.put(file.content.toByteArray()) // TODO: https://gitlab.com/ikeyan/plrv2/issues/3
                            }
                        } else {
                            println("New ${file.labels}: $id")
                            putNewFileToStorage(ossNode, file, id)
                        }
                    }
                    ossNode.syncAndWait()
                    listFilesInStorage(ossNode).forEach(::println)
                } else {
                    val res = Res()
                    println(res.format("accessing_account", plrId))
                    println("-----")
                    listFilesInStorage(ossNode).forEach(::println)
                    println("-----")
                }
            } finally {
                plr.destroy()
            }
        }

        private fun selectIdFromStorageList(plr: PLR): String {
            val list = plr.listStorages()
            val res = Res()
            return if (list.isEmpty()) {
                println(res.format("enter_new_id"))
                readLine()!!
            } else {
                list.forEachIndexed { index, s ->
                    println("[$index] ${s.typeName}:${s.userId}")
                }
                println(res.format("select_or_enter_new_id", 0, list.size-1))
                val line = readLine()!!
                try {
                    val sel = line.toInt()
                    "${list[sel].typeName}:${list[sel].userId}"
                } catch (e: NumberFormatException) {
                    line
                }
            }
        }
    }
}
