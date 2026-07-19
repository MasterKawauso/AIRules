# UE5 — Unreal Engine実装ルール

`*.uproject` があるプロジェクトで適用。

## 実装方針

- 中核ロジックはC++、Blueprintは配置・演出・調整・簡易接続を担当し、巨大なロジックを置かない
- 保守性・拡張性・速度を両立し、UE4知識をUE5へ未確認で適用しない

## 責務分離

- GameMode: サーバー側のルール・進行 / GameState: 共有試合状態
- PlayerController: 入力・固有操作窓口 / PlayerState: スコア・名前・チーム等の同期状態
- Character/Pawn: 移動・当たり判定・見た目の土台

## マルチプレイ前提

- マルチ前提の状態はGameState/PlayerStateに保持し、状態・入力・イベント・結果を同期する。View・SE・UI・演出を中心にしない

## 調査時に確認すること

- UEバージョン/C++かBlueprintか/EnhancedかLegacy Inputか
- GameMode・PlayerController・Pawn・Characterの割り当て、Mapに正しいGameModeが適用されているか
- Actorが配置済みか実行時Spawnか/BeginPlayが呼ばれているか/Tickが有効か
- Collision Preset/Object Channel/Trace Channel、ComponentのMobility/Visibility/Hidden In Game/Possess状態
- Editor設定とコード設定を分けて調査する

## 回答ルール

原因候補（優先順）→確認方法（Editor/C++/Blueprint別）→修正案。

未確認のUI・メニュー・設定名を断定しない。大規模修正や「再作成」を初手にせず、設計変更は提案に留める。
