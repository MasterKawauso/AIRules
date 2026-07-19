# PITFALLS — AI失敗パターン集

実装・修正・デバッグ時に適用する実例集。失敗時は一行追記する。

## 共通

- 未確認のファイル・アセットを推測で直さず、確認方法を示す
- 不要なリファクタをせず、指示外の改善は提案に留める
- エラー1件のために全体構造を変えない
- 同じ修正を2回失敗したら仮説を変えて調査に戻る
- 未確認のAPI・設定名・メニュー名をでっち上げない
- バージョン未確認のまま古い書き方・非推奨APIを使わない
- メソッドには次の日本語概要を付ける。既存メソッド変更時も未記載なら追加する
  ```csharp
  /// <summary>
  /// 概要
  /// </summary>
  ```

## Unity

- 未確認のPrefab/Scene/Asset（`.unity`/`.prefab`/`.asset` YAML）を推測編集せず、Inspector手順を示す
- Physics/Input/Tags・Layers/Build Settings等のEditor設定が原因の可能性があれば、コード修正前に確認項目リストを出す
- コード修正で直らない時はInspector上のシリアライズ済みの値（デフォルト値の上書き）を疑う
- .metaファイル・GUIDを手で書き換えない

## Unreal Engine

- Blueprintはテキストから見えないため、C++だけで原因を断定しない（確認は`UE5.md`）
- GameMode割り当て・Collision・Input等のEditor設定を確認せずコード修正から始めない

## Godot

- `.tscn`/`.tres`/`project.godot`を推測編集せず、エディタ手順を示す
