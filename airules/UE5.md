# UE5 — Unreal Engine実装ルール

`*.uproject` があるプロジェクトで適用。

## 実装方針

- 中核ロジックはC++、Blueprintは配置・演出・パラメータ調整・簡易接続を担当。Blueprintに巨大なゲームロジックを書かない
- UE作法だけでなく保守性・拡張性・実装速度のバランスを考慮。UE4知識をUE5へ断定適用しない

## 責務分離

- GameMode: ルール管理・開始終了判定等サーバー側進行 / GameState: 共有される試合状態
- PlayerController: 入力・プレイヤー固有操作窓口 / PlayerState: プレイヤーごとの同期状態（スコア・名前・チーム等）
- Character/Pawn: 移動・当たり判定・見た目の土台

## マルチプレイ前提

- マルチ前提の状態はGameState/PlayerStateに保持。View・SE・UI・演出は再現可能な表示として扱い同期対象の中心にしない
- 同期すべきは見た目ではなくゲーム状態・入力・イベント・結果

## 調査時に確認すること

- UEバージョン/対象がC++かBlueprintか/Enhanced InputかLegacy Inputか
- GameMode・PlayerController・Pawn・Characterの割り当て、Mapに正しいGameModeが適用されているか
- Actorが配置済みか実行時Spawnか/BeginPlayが呼ばれているか/Tickが有効か
- Collision Preset/Object Channel/Trace Channel、ComponentのMobility/Visibility/Hidden In Game/Possess状態
- Editor設定とコード設定を分けて調査する

## 回答ルール

1. 原因候補（優先度順） 2. 確認方法（Editor/C++/Blueprintを分ける） 3. 修正案

- 推測で断定しない（未確認のUI名・メニュー名・設定名を断定しない）。いきなり大規模修正や「再作成すれば直る」を出さない。勝手に設計変更せず提案に留める
