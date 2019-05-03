import com.assemblogue.plr.io.PlrEntry
import com.assemblogue.plr.io.Storage
import com.assemblogue.plr.io.StorageInfo
import com.assemblogue.plr.lib.EntityNode
import com.assemblogue.plr.lib.PLR
import com.assemblogue.plr.lib.model.Root
import com.assemblogue.plr.util.NodeSchemas

import java.io.FileReader
import java.io.IOException
import java.util.Collections
import java.util.Optional
import java.util.Properties

import javafx.scene.control.TextInputDialog
import javafx.application.Application
import javafx.application.Platform
import javafx.event.ActionEvent
import javafx.event.EventHandler
import javafx.scene.Scene
import javafx.scene.control.Button
import javafx.scene.control.TextArea
import javafx.scene.layout.StackPane
import javafx.stage.Stage

class App : Application() {
    private var plr: PLR = (PLR.createBuilder() as com.assemblogue.plr.lib.generic.PlrBuilder).build()
    private var textarea: TextArea = TextArea()

    override fun start(primaryStage: Stage) {
        primaryStage.setTitle("Hello World!")
        val btn = Button()
        btn.setText("Say 'Hello World'")
        btn.setOnAction(object : EventHandler<ActionEvent> {

            override fun handle(event: ActionEvent) {
                println("Hello World!")
            }
        })
        val root = StackPane()
        val scene = Scene(root, 300.0, 250.0)
        textarea.setWrapText(true)
        root.getChildren().add(btn)
        root.getChildren().add(textarea)
        primaryStage.setScene(scene)
        primaryStage.show()

        try {
            this.initialFetch()
        } catch (e: Exception) {
            e.printStackTrace()
            this.plr.destroy()
            throw RuntimeException(e)
        }

    }

    override fun stop() {
        this.plr.destroy()
        System.err.println("Application finished.")
    }

    private fun initialFetch() {
        val props = Properties()
        props.load(FileReader("config.properties"))

        val plrId: String = props.getProperty("plr.id")
        val storageId: String = plrId.split(":", limit = 2)[0]
        val userId = plrId.split(":", limit = 2)[1]
        val passphrase = props.getProperty("plr.passphrase", "")
        val storageInfo = plr.listStorages().filter { x: StorageInfo -> x.getTypeName() == storageId && x.getUserId() == userId }[0]
        val storage = plr.connectStorage(storageInfo)

        // ask passphrase if necessary
        if (!storage.hasKeyPair() && passphrase.length > 0) {
            storage.postPassphrase(passphrase)
        } else if (!storage.hasKeyPair()) {
            val dialog = TextInputDialog("walter")
            dialog.setTitle("Passphrase")
            dialog.setHeaderText("PLR asks for passphrase %s".format(plrId))
            dialog.setContentText("Please enter your passphrase:")

            val result = dialog.showAndWait()
            result.ifPresent({ storage.postPassphrase(it) })
        }

        val root = plr.getRoot(storage)
        root.sync(object : EntityNode.SyncCallback {
            override fun onError(entityNode: EntityNode, plrEntry: PlrEntry, e: Exception, origin: PlrEntry.Origin) {
                System.err.print("*")
                System.exit(1)
            }

            @Synchronized
            override fun onFinish(entityNode: EntityNode) {
                System.err.print(".")
            }

            override fun onUpdate(entityNode: EntityNode, origin: PlrEntry.Origin) {
                Platform.runLater({ textarea.setText(root.getAllProperties().toString()) })
            }
        })
    }

    companion object {
        @JvmStatic
        fun main(args: Array<String>) {
            Application.launch(*args)
        }
    }
}
