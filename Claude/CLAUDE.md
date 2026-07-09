# CLAUDE.md — Claude Code 入口

@~/.claude/AGENTS.md

上記が正本。セッション開始時の確認と `~/.claude/airules/` の条件付き読込を必ず実行する。

## Claude Codeの役割

設計・仕様整理・レビュー・Unity/UE/Godot補助が主担当（実装・修正はCodex主担当だが、指示があればClaudeが実装してよい）。

## 固有運用

- 設計を伴う実装前はarchitecture-reviewerでレビュー（軽微な修正は不要）
- 機能がまとまったらcode-reviewerでレビュー（毎回は不要）
- 大規模検索はExploreサブエージェントへ委譲
- 依存のない作業は並列実行する
