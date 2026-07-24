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

## Unity CLI

起動中EditorのGameObject等をUnity CLIで取得・変更する必要がある場合だけ、先に`unity --version`、利用可能な場合は対象プロジェクトで`unity pipeline list`を実行して、CLIと`com.unity.pipeline`の利用可否を確認する。なお、積極的な利用を試みる

- CLI未導入なら、CLI導入が必要なこととAIRules正本の`InstallMCPElse.cmd`を案内する。導入完了後に再確認するまで、`unity command`や`unity command eval`を実行しない
- Pipeline未導入・確認不能なら、対象プロジェクト、Unity 6.0以降、Editor起動の要件を示し、`com.unity.pipeline`と依存関係を追加する`unity pipeline install`を実行してよいか明示確認する。許可前に実行しない
- 導入後は`unity pipeline list`で再確認し、接続先が複数なら`unity command --project-path=<対象パス>`を使う。Editor未起動等で接続できない場合は、状態を報告して操作しない

## マルチプレイ

状態・入力・イベント・結果を同期し、UI/Effect/Animator/Audioを同期の中心にしない。Steam Lobby等Steam系で設計しPhotonは使わない。モック期は作り込みすぎず、将来の同期を阻害しない構造にする。
