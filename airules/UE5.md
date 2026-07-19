# UE5 — Unreal Engine実装

`*.uproject`があるプロジェクトで適用。

## 方針・責務

- 中核ロジックはC++、Blueprintは配置・演出・調整・簡易接続を担当する。UE4知識をUE5へ未確認で適用しない
- GameMode=サーバー側ルール/進行、GameState=共有試合状態、PlayerController=入力/固有操作窓口、PlayerState=スコア/名前/チーム等の同期状態、Character/Pawn=移動/当たり判定/見た目の土台
- マルチ前提の状態はGameState/PlayerStateに持ち、状態・入力・イベント・結果を同期する。View/SE/UI/演出を中心にしない

## 調査

必要範囲で、UEバージョン、C++/Blueprint、Enhanced/Legacy Input、GameMode/Controller/Pawn/CharacterとMap設定、配置/Spawn、BeginPlay/Tick、Collision/Channel、Mobility/Visibility/Hidden/Possessを確認し、Editor設定とコード設定を分けて原因を絞る。

回答は原因候補（優先順）→確認方法（Editor/C++/Blueprint別）→修正案。未確認のUI・設定名を断定せず、大規模修正・再作成を初手にしない。設計変更は提案に留める。
