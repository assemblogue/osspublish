import com.assemblogue.plr.io.Storage;
import com.assemblogue.plr.io.StorageInfo;
import com.assemblogue.plr.lib.EntityNode;
import com.assemblogue.plr.lib.PLR;
import com.assemblogue.plr.lib.model.Root;
import com.assemblogue.plr.util.NodeSchemas;

import java.io.FileReader;
import java.util.Collections;
import java.util.Optional;
import java.util.Properties;

import javafx.scene.control.TextInputDialog;

public class App {
    private static void run(PLR plr) throws Exception {
        Properties props = new Properties();
        props.load(new FileReader("config.properties"));

        String friendId = props.getProperty("plrId");
        String storageId = props.getProperty("plrStorageNumber", "1");

        // ストレージとルートの取得
        StorageInfo storageInfo = plr.listStorages().get(Integer.parseInt(storageId) - 1);
        Storage storage = plr.connectStorage(storageInfo);
        if (!storage.hasKeyPair()) {
            TextInputDialog dialog = new TextInputDialog("walter");
            dialog.setTitle("Text Input Dialog");
            dialog.setHeaderText("Look, a Text Input Dialog");
            dialog.setContentText("Please enter your passphrase:");

            Optional<String> result = dialog.showAndWait();
            result.ifPresent(storage::postPassphrase);
        }
        Root root = plr.getRoot(storage);
        System.err.println(storage.getUserId() + " -> " + friendId);
        System.err.print(".");

        // lifeRecord ノードの取得
        root.getNode().syncAndWait();
        EntityNode lifeRecordNode = root.getLifeRecordNode();
        if (lifeRecordNode == null) {
            throw new RuntimeException("life record node is not found");
        }
        if (!lifeRecordNode.isFolder()) {
            throw new RuntimeException("life record node is not folder");
        }
        System.err.print(".");

        // lifeRecordノードへのリンクをme-to-friendルートに追加
        EntityNode rootNode = root.getFriend(friendId).getMeToFriendRootNode();
        rootNode.syncAndWait();
        if (rootNode.getProperty(NodeSchemas.PROP_LIFE_RECORD).size() > 0) {
            throw new RuntimeException("lifeRecord property already exists");
        }
        rootNode.addProperty(NodeSchemas.PROP_LIFE_RECORD, lifeRecordNode);
        rootNode.syncAndWait();
        System.err.print(".");

        // lifeRecord を共有（読み取り・書き込み）
        storage.asSharable().share(
                lifeRecordNode.getEntry().getId(), false,
                Collections.singletonList(friendId.split(":", 2)[1]));
        System.err.print(".");

    }

    public static void main(String[] args) throws Exception {
        PLR plr = PLR.createBuilder().build();
        try {
            run(plr);

            // 終了処理
            plr.destroy();
            System.err.println("complete");
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace();
            plr.destroy();
            System.exit(1);
        }
    }
}
