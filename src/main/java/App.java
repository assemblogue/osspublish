import com.assemblogue.plr.io.PlrEntry;
import com.assemblogue.plr.io.Storage;
import com.assemblogue.plr.io.StorageInfo;
import com.assemblogue.plr.lib.EntityNode;
import com.assemblogue.plr.lib.PLR;
import com.assemblogue.plr.lib.model.Root;
import com.assemblogue.plr.util.NodeSchemas;

import java.io.FileReader;
import java.io.IOException;
import java.util.Collections;
import java.util.Optional;
import java.util.Properties;

import javafx.scene.control.TextInputDialog;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.TextArea;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;

public class App extends Application {
  private PLR plr;
  private TextArea textarea;
  
  @Override
  public void start(Stage primaryStage) throws Exception {
    primaryStage.setTitle("Hello World!");
    Button btn = new Button();
    btn.setText("Say 'Hello World'");
    btn.setOnAction(new EventHandler<ActionEvent>() {
        
        @Override
        public void handle(ActionEvent event) {
          System.out.println("Hello World!");
        }
      });
    StackPane root = new StackPane();
    Scene scene = new Scene(root, 300, 250);
    textarea = new TextArea();
    textarea.setWrapText(true);
    root.getChildren().add(btn);
    root.getChildren().add(textarea);
    primaryStage.setScene(scene);
    primaryStage.show();
    
    this.plr = null;
    try {
      this.plr = PLR.createBuilder().build();
      this.initialFetch();
    } catch (Exception e) {
      e.printStackTrace();
      if (this.plr != null)
        this.plr.destroy();
      throw new RuntimeException(e);
    }
  }

  @Override
  public void stop() throws IOException {
    if (this.plr != null)
      this.plr.destroy();
    System.err.println("Application finished.");
  }

  private void initialFetch() throws Exception {
    Properties props = new Properties();
    props.load(new FileReader("config.properties"));
    
    String plrId = props.getProperty("plr.id");
    String storageId = plrId.split(":", 2)[0];
    String userId = plrId.split(":", 2)[1];
    String passphrase = props.getProperty("plr.passphrase", "");
    
    // ストレージとルートの取得
    StorageInfo storageInfo = plr.listStorages().stream()
      .filter(x -> x.getTypeName().equals(storageId) && x.getUserId().equals(userId)).findFirst().get();
    Storage storage = plr.connectStorage(storageInfo);
    if (!storage.hasKeyPair() && passphrase != null && passphrase.length() > 0 ) {
      storage.postPassphrase(passphrase);
    } else if (!storage.hasKeyPair()) {
      TextInputDialog dialog = new TextInputDialog("walter");
      dialog.setTitle("Passphrase");
      dialog.setHeaderText("PLR asks for passphrase %s".format(plrId));
      dialog.setContentText("Please enter your passphrase:");
      
      Optional<String> result = dialog.showAndWait();
      result.ifPresent(storage::postPassphrase);
    }
    Root root = plr.getRoot(storage);
    root.sync(new EntityNode.SyncCallback() {
            @Override
            public void onError(EntityNode entityNode, PlrEntry plrEntry, Exception e, PlrEntry.Origin origin) {
                System.err.print("*");
                System.exit(1);
            }
        
            @Override
            public synchronized void onFinish(EntityNode entityNode) {
                System.err.print(".");
            }

            @Override
            public void onUpdate(EntityNode entityNode, PlrEntry.Origin origin) {
              Platform.runLater(() ->
                                textarea.setText(root.getAllProperties().toString()));
            }
      });
  }
  
  public static void main(String[] args) {
    launch(args);
  }
}
