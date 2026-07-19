# REVIEW — コードレビュールール

コードレビュー時に適用。`REVIEW_STATE.md`更新以外は変更せず指摘だけ行う。一般論より`PLAN.md`・設計・開発フェーズを優先する。

## 進め方

1. `REVIEW_STATE.md`があれば前回以降、なければ今回セッションの実装だけを対象にする。蓄積した全diffへ広げない
2. `PLAN.md`の仕様項目ごとに準拠を確認する
3. 該当観点だけ確認する
4. `REVIEW_STATE.md`へ日時・レビュー済み仕様・ファイルを数行で記録する

## スコープ

- 範囲内だけ指摘する。範囲外は重大な問題のみ「対象外の気づき」として一行記し、詳しく調べない

## 指摘の基準

- 動作・仕様・保守性に実害があるものだけ指摘し、実害を一行で示す。示せなければ指摘しない
- 好み・スタイルの指摘はしない（airules/やプロジェクト規約違反は指摘してよい）
- 推測で断定しない。未確認の指摘は「未確認」と明記する

## 出力形式

仕様別OK/NGと理由 → 重要順の指摘（実害・修正案） → 対象外の気づき（任意）。指摘なしは「問題なし」。重大度・点数は任意。

## 観点（該当するものだけ）

- Architecture: 設計準拠/責務/依存・循環/SOLID/フェーズに対する抽象化・共通化の重さ/保守・拡張性
- Safety: Null/Dispose/イベント購読解除漏れ/例外処理/ログ
- Performance: Update・Tick/Alloc・GC/不要な検索（Find・GetComponent・Dictionary）/LINQ・foreach Alloc/可読性を損なう過剰最適化
- Readability: 命名/コメント/メソッド長/クラス責務
- Gameplay: ゲーム性/UI・UX/演出/調整しやすさ
- Unity限定: MonoBehaviour肥大化/Inspector運用/ScriptableObject利用/Unity依存の適切さ/Addressables考慮
- UE限定: Blueprint肥大化/C++との責務分離/GameMode・GameState・PlayerController・PlayerStateの責務/Enhanced Input/Replication・RPC/Tick乱用
- Multiplayer前提時のみ: 同期対象の妥当性（ローカル状態・見た目を同期していないか）/拡張性
