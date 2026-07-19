# UNITY — Unity実装ルール

`Assets/`・`*.unity`・`*.asmdef` があるプロジェクトで適用。

## アーキテクチャ

- 規模に応じMVP/MVC/Clean Architecture等を選ぶ。モック期は速度優先で過剰設計を避ける
- 本実装期・共通モジュールはMonoBehaviour等を薄い層に閉じ、ロジックをUnity非依存・差替可能にする。マルチプレイ同期を阻害しない
- DIコンテナは必要になってから導入する

## AIが扱いやすい構成

- 1ファイル1クラス、目安200〜400行・500行超で分割検討。`partial`は原則使わない
- ゲームロジックはPure C#、MonoBehaviourは接着剤とし、EditModeテスト可能にする
- ファイル名＝クラス名。役割と場所が予測できる命名にする（`Mgr`等の省略語禁止）
- フォルダはフィーチャー別を優先（例`Scripts/Enemy/`にModel・View・Data）
- asmdefは`Core/Game/View/Editor/Tests`程度の機能単位で分割（依存違反をコンパイルエラーで検出）。過剰分割はしない
- シーン・Prefabは配置だけに寄せ、配線・初期化・生成はコードで行う
- デフォルト値はコードかScriptableObjectに置き、Inspectorでの値上書きを増やさない

## 名前空間

- `KawausoForge.プロジェクト名.フォルダ階層`

## 実装

- Viewは表示、Modelは状態を担当し、MonoBehaviourへ複雑なロジックを書かない
- 参照はAwake/Start/Init/Inspectorで確定する。Update内のGetComponent/Find系は禁止し、他でも原則避ける
- Viewは直呼びよりAction等のイベント購読を優先。更新はModelの`Tick(float deltaTime)`へ集約しUpdateを最小化する
- privateメンバーは`private`を明記する

## ScriptableObject

- マスターデータ・設定・バランス調整に使い、ランタイム状態・セーブには使わない

## UI・共通コンポーネント

- テキスト=`KawausoText`、ボタン=`KawausoButton`（`KawausoForge.Extension`）、ログ=`KawausoDebug.Log`
- `CommonComponents`がある場合: シーン移動は`SceneHandler`利用、各シーン最上位クラスは`AbstractSceneHandler`継承

## マルチプレイ

- 状態・入力・イベント・結果を同期し、UI・Effect・Animator・Audioを中心にしない
- 同期はSteam Lobby等Steam系で設計（Photonは使わない）。モック期はネットワーク実装を作り込みすぎない
