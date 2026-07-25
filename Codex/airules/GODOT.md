# GODOT — Godot実装

`project.godot`があるプロジェクトで適用。

- Godot 3/4、GDScript/C#を確認する。C#メンバーはアンダースコアなし小文字始まり、GDScriptはsnake_case
- Sceneは再利用可能な単一責務に分け、「下へ呼出し、上へSignal」を基本とする。親・兄弟依存や`get_node`固定パスよりSignal・`@export`を優先する
- Sound/遷移/設定等はAutoloadへ集約し、ゲーム固有コードと分ける（`GAME_COMMON.md`）
- `_process`/`_physics_process`内の重い検索・生成を避け、値・パスは`@export`変数/Resourceで調整可能にする
