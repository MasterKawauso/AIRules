# UNITY — Unity実装ルール

`Assets/`・`*.unity`・`*.asmdef` があるプロジェクトで適用。

## アーキテクチャ

- 規模に応じてMVP・MVC・Clean Architecture等から選ぶ（固定しない）。モック期は実装速度優先、過剰設計を避ける
- 本実装期・共通モジュールではUnity依存(MonoBehaviour等)を薄い層に隠蔽しロジックはUnity非依存に寄せる。将来のマルチプレイ同期を阻害しない設計を意識
- DIコンテナは必要になってから導入。共通モジュールはインターフェース公開で差し替え可能に

## 推奨する構成（AIファースト。AIから見えない/読み切れない単位を減らす）

- 1ファイル1クラス、目安200〜400行・500行超で分割検討。`partial`は原則使わない
- ゲームロジックはPure C#（Unity非依存）に置きMonoBehaviourは接着剤に徹する（EditModeテストで自己検証可）
- ファイル名＝クラス名。役割と場所が予測できる命名にする（`Mgr`等の省略語禁止）
- フォルダはレイヤー別よりフィーチャー別（例`Scripts/Enemy/`にModel・View・Data同居）
- asmdefは`Core/Game/View/Editor/Tests`程度の機能単位で分割（依存違反をコンパイルエラーで検出）。過剰分割はしない
- シーン・Prefabは「配置の器」に徹し配線・初期化・生成はコードで行う（.unity/.prefabはAIから見えないため）
- デフォルト値はコードかScriptableObjectに置き、Inspectorでの値上書きを増やさない

## 名前空間

- `KawausoForge.プロジェクト名.フォルダ階層`

## 実装

- MonoBehaviourに複雑なロジックを書きすぎない（Viewは表示、Modelは状態管理）
- 参照はAwake/Start/Init/Inspectorで確定。Update内でのGetComponent/Find系は禁止、それ以外でも原則使わない
- View層はメソッド直呼びよりAction等のイベント購読を優先。ゲーム更新はModelの`Tick(float deltaTime)`に集約しUpdateは最小限に

## ScriptableObject

- マスターデータ・設定値・バランス調整用に使う。ランタイム状態・セーブデータには使わない

## UI・共通コンポーネント

- テキストは`KawausoText`、ボタンは`KawausoButton`（`using KawausoForge.Extension`）、ログは`KawausoDebug.Log`を使う
- `CommonComponents`がある場合: シーン移動は`SceneHandler`利用、各シーン最上位クラスは`AbstractSceneHandler`継承

## マルチプレイ

- 同期対象はViewでなくゲーム状態（状態・入力・イベント・結果）。UI・Effect・Animator・Audioを同期対象の中心にしない
- 同期はSteam Lobby等Steam系で設計（Photonは使わない）。モック期はネットワーク実装を作り込みすぎない
