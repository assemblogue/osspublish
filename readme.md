オントロジーを配置するためのツールです。

SpreadSheet.docx - スプレッドシートの書式の定義文書です。

osscon-all.jar - コマンドラインに渡したOSSを、自分のPLRアカウントの所定の位置に配置するツールです。必要に応じて下記のURLを呼び出します。

https://osspublish.fly.dev - スプレッドシート(xlsx)をJSONLDの束(zip)に変換する外部サーバーです。


## ビルド方法

osscon-all.jar を作成するには https://drive.google.com/drive/u/0/folders/182s6nytpYtOHoNH-0ko6ggIV8otCMGoI の `plr2_lib_generic.jar` を libs/ に配置してから、下記のコマンドを使ってください。

    gradle shadowJar

## 使用方法（外部サーバー利用）

config.properties ファイルに下記のような内容を用意してください（アカウント名は自分のものにしてください）。

    plr.id=googleDrive:matsubara.plr@gmail.com

スプレッドシート Sample.xlsx を引数とする場合は下記のようなコマンドで起動してください。

    java -jar osscon-all.jar Sample.xlsx

この方法を使うと、起動のたびに `osspublish.fly.dev` にアクセスします。

## 使用方法（ローカルサーバー利用）

config.properties ファイルに下記のような内容を用意してください（アカウント名は自分のものにしてください）。

    plr.oss.endpoint=http://localhost:18888/convert
    plr.id=googleDrive:matsubara.plr@gmail.com

下記のようなdockerコマンドを使うか、同様の環境を作ってサーバーを立ち上げてください（Dockerfile に詳細が書いてあります）。

    docker build -t osspublish . && docker run -e PORT=18888 -p 18888:18888 -it osspublish

スプレッドシート Sample.xlsx を引数とする場合は下記のようなコマンドで起動してください。

    java -jar osscon-all.jar Sample.xlsx

## 注意点

- Personaryでアカウントの初期設定が済んでいない場合は、してください。
- config.properties はカレントディレクトリに作成してください。
- OSSファイルを削除する機能がまだありません。下記のplrコマンドをお使いください。public root を開き、oss 以下にあるファイルから、削除したいものを探して削除してください。
  
  plr.zip, plr_manual.txt:
  https://drive.google.com/drive/u/0/folders/182s6nytpYtOHoNH-0ko6ggIV8otCMGoI
  
- 初回更新後に `EntryNotFoundException` が表示される場合は、おそらく作成自体は成功しています。
- タイムアウトが表示される場合、しばらく待ってからもう一度試してみてください。
