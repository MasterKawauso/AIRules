# GODOT — Godot実装ルール

`project.godot` があるプロジェクトで適用。

- Godot 3/4とGDScript/C#を確認してから回答する。C#メンバーはアンダースコアなし小文字始まり、GDScriptはsnake_case
- シーンは再利用可能な単一責務で分割。「下へ呼出し、上へシグナル」を基本に、親・兄弟依存や`get_node`ハードパスよりシグナル・`@export`を優先する
- サウンド・遷移・設定等はAutoloadへ集約し、ゲーム固有コードと分ける（`GAME_COMMON.md`）
- `_process`/`_physics_process`内の重い検索・生成を避け、値・パスは`@export`変数/リソースで調整可能にする
