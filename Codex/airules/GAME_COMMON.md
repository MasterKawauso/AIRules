# GAME_COMMON — 共通モジュール設計

全ゲーム実装・修正に適用するエンジン非依存方針。詳細は`UNITY.md`/`UE5.md`/`GODOT.md`。

ゲーム固有コードと共通機能を分ける。他ゲームでも使う可能性が高い機能だけ共通化し、モック期、2〜3回の重複、将来予測だけでは抽象化しない。

| 共通化候補 | 内容 |
|---|---|
| Scene/UI/Loading | Load/Unload・遷移・Fade・Panel/Stack/Popup・非同期進捗 |
| Sound/Effect | BGM/SE/音量/汎用SEボタン・VFX Pool/再生/停止 |
| 設定/多言語 | 音量・解像度・言語保存、Localization、UIText追従 |
| Save/Master | Save CRUD、Item/Character等の静的定義 |
| Steam/Multiplayer | 実績・ランキング・Lobby・P2P・Friend・Session・同期・RPC |
| Input | Keyboard/Pad/Touch抽象化・Remap |

## 設計

- 依存は`ゲーム固有 → 共通モジュール → エンジン/SDK`。逆参照・循環を作らない
- 共通モジュールは独立名前空間（例`KawausoForge.Core`）に置き、Unityは`.asmdef`で依存を明示する
- 本実装期までに必要な公開境界をinterface化して差替可能にする。モック期は任意
- Steamはラッパー経由、Unityに`CommonComponents`があれば優先する

実装前に、ゲーム固有知識の混入、ゲーム固有クラスへの逆参照、別Projectへ移せる境界、循環、必要なmock差替（本実装期）を確認する。問題がなければチェック結果を列挙しない。
