# CLAUDE.md — Claude Code 入口

@~/.claude/AGENTS.md

上記が正本。開始時確認と`~/.claude/airules/`の条件付き読込を行う。

## Claude Codeの役割

主担当は設計・仕様・レビュー・ゲームエンジン補助。実装・修正はCodex主担当だが、指示時はClaudeも行う。

## 固有運用

- 設計を伴う実装前は`architecture-reviewer`、機能単位の完了時は`code-reviewer`を使う。軽微な修正・毎回の呼出しは不要
- 大規模検索はExploreへ委譲し、独立作業は並列化する
