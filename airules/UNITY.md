# UNITY — Unity実装

`Assets/`・`*.unity`・`*.asmdef`があるプロジェクトで適用。

## 構成

- 規模に応じMVP/MVC/Clean Architecture等を選び、モック期は過剰設計を避ける。本実装期・共通モジュールはMonoBehaviour等を薄い接着層にし、ロジックをUnity非依存・差替可能にする。DIコンテナは必要後に導入する
- 1ファイル1クラス、目安200〜400行・500行超で分割検討。`partial`は原則使わない
- ゲームロジックはPure C#でEditModeテスト可能にする。ファイル名=クラス名、役割と場所が分かる命名（`Mgr`等の略語禁止）、フィーチャー別フォルダを優先する
- asmdefは`Core/Game/View/Editor/Tests`程度に分け、循環を避ける。Scene/Prefabは配置中心、配線・初期化・生成はコード、既定値はコードかScriptableObjectに置く
- 名前空間は`KawausoForge.プロジェクト名.フォルダ階層`

## 実装

- View=表示、Model=状態。参照はAwake/Start/Init/Inspectorで確定し、Update内のGetComponent/Findは禁止、他でも原則避ける
- ViewはAction等のイベント購読を優先し、更新はModelの`Tick(float deltaTime)`へ集約してUpdateを最小化する。privateメンバーは`private`を明記する
- ScriptableObjectはマスターデータ・設定・調整値に使い、ランタイム状態・セーブには使わない
- テキスト=`KawausoText`、ボタン=`KawausoButton`（`KawausoForge.Extension`）、ログ=`KawausoDebug.Log`
- `CommonComponents`があれば、Scene遷移は`SceneHandler`、各Scene最上位は`AbstractSceneHandler`を使う

## マルチプレイ

状態・入力・イベント・結果を同期し、UI/Effect/Animator/Audioを同期の中心にしない。Steam Lobby等Steam系で設計しPhotonは使わない。モック期は作り込みすぎず、将来の同期を阻害しない構造にする。
