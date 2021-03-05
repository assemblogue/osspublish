import com.assemblogue.plr.io.Storage
import com.assemblogue.plr.lib.EntityNode
import com.assemblogue.plr.lib.FileNode
import com.assemblogue.plr.lib.PLR
import com.assemblogue.plr.lib.model.PublicRoot
import com.assemblogue.plr.util.NodeSchemas
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlin.io.path.ExperimentalPathApi
import org.apache.poi.ss.usermodel.WorkbookFactory
import java.io.File
import java.io.FileReader
import java.io.FileWriter
import java.net.URL
import java.security.MessageDigest
import java.text.MessageFormat
import java.time.Instant
import java.util.*
import java.util.zip.ZipFile
import java.util.concurrent.TimeUnit

data class FileToUpload (
	val linkName: String, val id: String, val labels: Map<String, String>,
	val format:String="application/ld+json", val content:String="")

data class FileInStorage (
	val linkName: String, val labels: Map<String, String>,
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
		formatter.applyPattern(
			ResourceBundle.getBundle("messages", XMLResourceBundleControl())
				.getString(messageId))
		return formatter.format(args)
	}
}



class Client {
	companion object {
		val res = Res()

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
			val id = node.get("id").asText()
			val labels = parseLabels(node.get("label")!!)
			return FileToUpload(linkName, id, labels, format,
					fileEntries[file!!] ?: error("referencing non-existing file"))
		}

		fun filesToUpload(node: JsonNode, fileEntries: Map<String, String>): List<FileToUpload> {
			return NodeSchemas.PROP_OSS_CONTAINERS.flatMap { linkName ->
				if (node.has(linkName)) {
				node.get(linkName).let { n -> (0 until n.size()).map {
					parseFileToUpload(linkName, n.get(it), fileEntries)
				} } } else {
					listOf()
				}
			}
		}

		fun getPropOssOrCreate(root: PublicRoot): EntityNode {
			val c = root.getProperty(NodeSchemas.PROP_OSS).filter { it.isEntity() && it.asEntity().isInner() }.map { it.asEntity() }
			when (c.size) {
				0 -> {
					val ossNode = root.node.newInnerEntity(
						NodeSchemas.PROP_OSS,
						NodeSchemas.CLASS_OSS
					)
					root.node.syncAndWait()
					return ossNode
				}
				1 -> {
					return c[0]
				}
				else -> {
					System.err.println("more than one oss node: " + c)
					return c[0]
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

		fun getPassphraseEntered(): String {
			println(res.format("enter_passphrase"))
			return readLine()!!
		}

		fun authenticateAndGetStorage(plr: PLR, plrId: String, passphrase: String?): Storage? {
			val (storageType, userId) = try {
				plrId.split(":", limit = 2).let{ a -> Pair(a[0], a[1])}
			} catch (e: IndexOutOfBoundsException) {
				error("invalid user id $plrId; use this format: googleDrive:foobar@gmail.com")
			}
			val storages = plr.listStorages().filter {
				x -> x.typeName == storageType && x.userId == userId
			}
			try {
				return if (storages.isNotEmpty()) {
					plr.connectStorage(storages[0])
				} else {
					plr.newStorage(Storage.Type.byName(storageType))
				}
			} catch (e: PLR.StorageNeedPassphraseException) {
				val p = passphrase ?: getPassphraseEntered()
				return e.postPassphrase(p.toByteArray())
			}
		}

		fun generateOssId(linkName: String, labels: Map<String, String>, baseName: String, userId: String): String {
			val key = arrayOf('"'+ linkName+'"',
					labels.filter{(k,_) -> k == "ja" || k == ""}.map{ (k, v) -> "[\"$k\", \"$v\"]"}
			).joinToString(", ", "[", "]")
			return "$userId#" + Hasher().sha256(key).substring(0..15) + "#${baseName}_$linkName"
		}

		fun generateOssId(file: FileInStorage): String {
			return file.node.peerEntity.getProperty(NodeSchemas.PROP_OSS_ID)[0].asLiteral().value.toString()
		}
		fun generateOssId(file: FileToUpload, userId: String): String {
			return generateOssId(file.linkName, file.labels, file.id, userId)
		}

		fun normalizeOssId(s: String): String {
			val m = Regex("(.*?)#(.*?)#(.*)").matchEntire(s)
			return if (m != null) {
				listOf(m.groups[1], m.groups[2]).map{it!!.value}.joinToString("#")
			} else {
				s
			}
		}

		@OptIn(ExperimentalPathApi::class)
		fun convertUsingOnlineService(content: ByteArray, name: String, endpoint: URL): Map<String, String> {
			val client = OkHttpClient.Builder()
					.connectTimeout(60000L, TimeUnit.MILLISECONDS)
					.callTimeout(60000L, TimeUnit.MILLISECONDS)
					.readTimeout(60000L, TimeUnit.MILLISECONDS)
					.build()
			val requestBody = MultipartBody.Builder().setType(MultipartBody.FORM)
					.addFormDataPart(
						"file", name,
						content.toRequestBody("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".toMediaType()))
					.build()
			val request = Request.Builder()
					.url(endpoint)
					.post(requestBody)
					.build()
			val response = client.newCall(request).execute()
			val bytes = response.body!!.bytes()
			val file = kotlin.io.path.createTempFile("oss", ".zip").toFile()
			file.writeBytes(bytes)
			System.err.println("temp file: $file")
			return unzipFile(file)
		}

		fun listFilesInStorage(ossNode: EntityNode): Sequence<String> {
			return filesInStorage(ossNode).asSequence().map { file ->
				val (ver, date) = file.node.entry.let {
					try {
						Pair(it.listRevisions().size, Instant.ofEpochMilli(it.getMeta()?.lastModified() ?: 0L))
					} catch (e: com.assemblogue.plr.io.EntryNotFoundException) {
						Pair(-1, Instant.ofEpochMilli(0L))
					}
				}
				"${file.linkName} v$ver $date ${generateOssId(file)} ${file.labels}"
			}
		}

		fun findConfigOrCreate(file: File, defaults: Map<String, String>): Properties {
			return if (file.exists()) {
				Properties().also{ props ->
					props.load(FileReader(file))
					defaults.forEach{ (k, v) ->
						if (props.getProperty(k) == null) {
							props.setProperty(k, v)
						}
					}
				}
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
			val fileNode = ossNode.newFile(file.linkName, file.format, true)
			fileNode.put(file.content.toByteArray())
			fileNode.titleValueMap = file.labels
			fileNode.peerEntity.newLiteral(NodeSchemas.PROP_OSS_ID).value = id
		}

		fun selectIdFromStorageList(plr: PLR): String {
			val list = plr.listStorages()
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

		fun findExportUrl(url: String): String {
			return url.replace(Regex("(https://docs\\.google\\.com/spreadsheets/.*)/(edit|view)([#\\?].*|)"), "$1/export")
		}

		fun findOntologyName(bytes: ByteArray): String {
			val wb = WorkbookFactory.create(bytes.inputStream())
			val sheet = wb.getSheetAt(0)
			val text = sheet.getRow(0).getCell(0).stringCellValue
			return text.split(Regex("\\s"), 3)[1]
		}

		@JvmStatic
		fun main(args: Array<String>) {
			var returnCode = 0
			val plr = PLR.createBuilder<PLR.Builder>().build()
			val props = findConfigOrCreate(
					File("config.properties"),
					mapOf(
						"plr.oss.endpoint" to "https://osscon.herokuapp.com/convert",
						"verbose" to "false")
			)
			val plrId = props.getProperty("plr.id") ?: selectIdFromStorageList(plr)
			val passphrase = props.getProperty("plr.passphrase")
			val verbose = props.getProperty("verbose").toBoolean()

			try {
				val storage = authenticateAndGetStorage(plr, plrId, passphrase)!!
				val root = plr.getPublicRoot(storage)
				root.syncAndWait()
				val ossNode = getPropOssOrCreate(root)

				if (args.isNotEmpty()) {
					args.forEach { arg ->
						val fileEntries = when {
							arg.startsWith("http") -> {
								val client = OkHttpClient()

								val request = Request.Builder()
										.url(findExportUrl(arg))
										.get()
										.build()
								val response = client.newCall(request).execute()
								val responseBody = response.body
								if ( responseBody == null || responseBody.contentType().toString() != "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") {
									println(res.format("spreadsheet-not-retrieved", arg))
									throw java.io.IOException("Spreadsheet not retrieved: " + arg)
								}
								val bytes = responseBody.bytes()
								convertUsingOnlineService(
									bytes,
									findOntologyName(bytes) + ".xlsx",
									URL(props.getProperty("plr.oss.endpoint"))
								)
							}
							arg.endsWith(".xlsx") || arg.endsWith(".csv") -> convertUsingOnlineService(
								File(arg).readBytes(),
								File(arg).name,
								URL(props.getProperty("plr.oss.endpoint"))
							)
							arg.endsWith(".zip") -> unzipFile(File(arg))
							else -> {
								println(res.format("file-not-supported", arg))
								throw java.io.IOException("File not supported: " + arg)
							}
						}
						val filesToUpload = filesToUpload(
								ObjectMapper().readTree(fileEntries["index.json"] as String), fileEntries
						).associate { Pair(generateOssId(it, storage.userId), it) }
						val filesInStorage = filesInStorage(ossNode).associate { x -> Pair(normalizeOssId(generateOssId(x)), x) }
						filesToUpload.forEach { (id, file) ->
							if (filesInStorage.contains(normalizeOssId(id))) {
								println(res.format("overwriting", file.labels, id))
								filesInStorage.getValue(normalizeOssId(id)).node.let { n ->
									if (n.get().readBytes().contentEquals(file.content.toByteArray())) {
										println(res.format("skipped_unchanged"))
									} else {
										n.put(file.content.toByteArray())
									}
								}
							} else {
								println("New ${file.labels}: $id")
								putNewFileToStorage(ossNode, file, id)
							}
						}
					}
					ossNode.syncAndWait()
					if (verbose) {
						listFilesInStorage(ossNode).forEach(::println)
					}
				} else {
					println(res.format("accessing_account", plrId))
					if (verbose) {
						println(Instant.ofEpochMilli(ossNode.meta.lastModified()))
						ossNode.entry.getSharingUsers().forEach {
							println(it)
						}

					}
					println("-----")
					listFilesInStorage(ossNode).forEach(::println)
					println("-----")
				}
			} catch (e: Exception) {
				e.printStackTrace()
				returnCode = 1
			} finally {
				plr.destroy()
				kotlin.system.exitProcess(returnCode)
			}
		}
	}
}
