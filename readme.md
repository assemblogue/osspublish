オントロジーを配置するためのツールです。

SpreadSheet.docx - スプレッドシートの書式の定義文書です。

osscon-all.jar - コマンドラインに渡したOSSを、自分のPLRアカウントの所定の位置に配置するツールです。必要に応じて下記のURLを呼び出します。

https://osscon.herokuapp.com - スプレッドシート(xlsx)をJSONLDの束(zip)に変換するツールです。


## ビルド方法

osscon-all.jar を作成するには下記のコマンドを使ってください。

     gradle shadowJar


     java -jar osscon-all.jar Sample.xlsx


## 使用方法（外部サーバー利用）

     plr.id=googleDrive:matsubara.plr@gmail.com
