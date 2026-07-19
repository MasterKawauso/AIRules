# CLAUDE.md — Claude Code入口

@~/.claude/AGENTS.md

上記を正本とし、開始時確認と必要な`~/.claude/airules/`だけを1回読む。

主担当は設計・仕様・レビュー・ゲームエンジン補助。実装・修正はCodex主担当だが、ユーザー指示時はClaudeも行う。

- `WORKFLOW.md`対象の設計は`architecture-reviewer`、機能差分は`code-reviewer`で確認する。軽微な変更や同じ差分への重複起動は不要
- 大規模検索はExploreへ、独立作業は範囲と成果物を限定して委譲・並列化する
