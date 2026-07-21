# PITFALLS — AI失敗パターン

実装・修正・デバッグ時に適用。再発性のある新規パターンは、同リポジトリが作業範囲なら正本へ一行追記する。

## 共通

- 未確認のファイル・アセット・API・設定名・メニュー名を推測で直したり捏造せず、確認方法を示す
- 指示外の改善・リファクタは提案に留め、1エラーのために全体構造を変えない
- 同じ修正が2回失敗したら仮説を変えて調査へ戻る
- バージョン確認なしに古い記法・非推奨APIを使わない
- 追加・変更したC#メソッドに日本語概要がなければ、既存規約どおり
/// <summary>
/// メソッド説明。
/// </summary>
/// <param name="value">value引数説明。</param>
/// <param name="count">count引数説明。</param>
/// <returns>返り値説明。</returns>
のようにメソッド、引数、返り値の説明を付ける。未変更メソッドへ広げない

## エンジン別

- Unity: 未確認の`.unity`/`.prefab`/`.asset` YAMLや`.meta`/GUIDを推測編集しない。Physics/Input/Tags・Layers/Build SettingsやInspector値が原因になり得る場合はコード修正前に確認する
- Unreal Engine: 不可視のBlueprintをC++だけで断定しない。GameMode/Collision/Input等のEditor設定を先に確認する（`UE5.md`）
- Godot: `.tscn`/`.tres`/`project.godot`を推測編集せず、必要ならエディタ手順を示す
