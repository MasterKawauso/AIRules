# PITFALLS — AI失敗パターン

実装・修正・デバッグ時に適用。再発性のある新規パターンは、同リポジトリが作業範囲なら正本へ一行追記する。

## 共通

- 未確認のファイル・アセット・API・設定名・メニュー名を推測で直したり捏造せず、確認方法を示す
- 指示外の改善・リファクタは提案に留め、1エラーのために全体構造を変えない
- 同じ修正が2回失敗したら仮説を変えて調査へ戻る
- バージョン確認なしに古い記法・非推奨APIを使わない
- Codexの現在モデルを`config.toml`やWorker起動時の指定値から推測しない。設定値と実行中値はセッション上書き等で異なり得る
- 説明コメントを省略しない。追加・変更したメソッド・関数とメンバー変数には日本語の説明を付ける（`AGENTS.md`実装・検証）。C#は
/// <summary>
/// メソッド説明。
/// </summary>
/// <param name="value">value引数説明。</param>
/// <param name="count">count引数説明。</param>
/// <returns>返り値説明。</returns>
のように改行し、メンバー変数にも`/// <summary>`で意味を書く。`<remarks>`は原則使わず、補足も`<summary>`へ収める。未変更箇所へ広げない

## エンジン別

- Unity: 未確認の`.unity`/`.prefab`/`.asset` YAMLや`.meta`/GUIDを推測編集しない。Physics/Input/Tags・Layers/Build SettingsやInspector値が原因になり得る場合はコード修正前に確認する
- Unreal Engine: 不可視のBlueprintをC++だけで断定しない。GameMode/Collision/Input等のEditor設定を先に確認する（`UE5.md`）
- Godot: `.tscn`/`.tres`/`project.godot`を推測編集せず、必要ならエディタ手順を示す
