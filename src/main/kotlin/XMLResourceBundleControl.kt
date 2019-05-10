import java.util.Collections
import java.util.Locale
import java.util.ResourceBundle
import java.util.Properties
import java.util.Enumeration


class XMLResourceBundleControl : ResourceBundle.Control() {

    private val XML = "xml"

    override fun newBundle(baseName: String, locale: Locale, format: String, loader: ClassLoader, reload: Boolean): ResourceBundle {

        if (format != XML) {
            throw IllegalArgumentException("format must be xml")
        }

        val bundleName = toBundleName(baseName, locale)
        val resourceName = toResourceName(bundleName, format)
        val connection = loader.getResource(resourceName).openConnection()

        if (reload) {
            connection!!.useCaches = false
        }

        val props = Properties()
        props.loadFromXML(connection!!.getInputStream().buffered())

        return object: ResourceBundle() {

            override fun handleGetObject(key: String): Any {
                return props.getProperty(key)
            }

            override fun getKeys(): Enumeration<String> {
                return Collections.enumeration(props.stringPropertyNames())
            }

        }
    }

    override fun getFormats(baseName: String): List<String> {
        return listOf(XML)
    }

}
