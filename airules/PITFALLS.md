# PITFALLS — AI失敗パターン集

実装・修正・デバッグ時に適用。過去にAIが実際に失敗したパターン集。**失敗したら一行追記して育てる。**

## 共通

- 見えないファイル・アセットを推測で修正しない。確認方法を提示する
- 不要なリファクタで変更範囲を広げない。指示外の改善は提案に留める
- エラー1件のために全体構造を変えない
- 同じ修正を2回失敗したら仮説を変えて調査に戻る
- 未確認のAPI・設定名・メニュー名をでっち上げない
- バージョン未確認のまま古い書き方・非推奨APIを使わない
- メソッドには
///<summary>
///xxx
///</summary>
の形で概要を記載する（既存メソッド変更時もなければつける）

## Unity

- 見えないPrefab/Scene/Asset(.unity/.prefab/.assetのYAML)を推測で直接編集しない。Inspector操作手順を提示する
- Physics/Input/Tags・Layers/Build Settings等のEditor設定が原因の可能性があれば、コード修正前に確認項目リストを出す
- コード修正で直らない時はInspector上のシリアライズ済みの値（デフォルト値の上書き）を疑う
- .metaファイル・GUIDを手で書き換えない

## Unreal Engine

- Blueprintの中身はテキストから見えない。C++だけで原因を断定しない（確認手順はUE5.md）
- GameMode割り当て・Collision・Input等のEditor設定を確認せずコード修正から始めない

## Godot

- .tscn/.tres/project.godotを推測で直接書き換えない。エディタ操作手順を提示する
