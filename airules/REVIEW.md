# REVIEW — コードレビュー

レビュー時に適用。依頼がレビューだけなら`REVIEW_STATE.md`更新以外は変更しない。一般論より`PLAN.md`・設計・開発フェーズを優先する。

## 範囲と手順

1. `REVIEW_STATE.md`があれば前回以降、なければ今回の変更だけを見る。蓄積した全diffへ広げない
2. 仕様項目と該当観点を差分に照らす
3. 実害のある問題だけ、根拠を確認して報告する
4. 複数セッションでレビュー範囲を引き継ぐ場合だけ`REVIEW_STATE.md`へ日時・確認済み仕様・ファイルを数行で記す。単発レビューでは作らない

範囲外は重大な問題だけ「対象外の気づき」として一行記し、深掘りしない。好み・スタイルは指摘せず、規約違反は指摘できる。推測は断定せず「未確認」とする。

## 出力

問題があれば重要順に、対象/実害/根拠/最小修正案を示す。なければ「問題なし」と検証範囲を一行で示す。仕様別OK一覧、重大度、点数は求められた場合だけ出す。

## 観点（該当分だけ）

- Architecture: 設計・責務・依存/循環・フェーズに対する抽象化の重さ・保守/拡張性
- Safety: Null、Dispose、イベント解除、例外、ログ
- Performance: Update/Tick、Alloc/GC、不要な検索、LINQ/foreach Alloc、過剰最適化
- Readability: 命名、コメント、メソッド長、クラス責務
- Gameplay: ゲーム性、UI/UX、演出、調整容易性
- Unity: MonoBehaviour、Inspector、ScriptableObject、Unity依存、Addressables
- UE: Blueprint/C++責務、GameMode系責務、Enhanced Input、Replication/RPC、Tick
- Multiplayer前提時: 同期対象の妥当性と拡張性
