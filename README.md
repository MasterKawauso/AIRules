# AIRules

Codex CLI と Claude Code の開発ルールを一元管理し、両ツールへ配備するリポジトリ。

## 構成

```
AIRules/
├── AGENTS.md            # 共通方針の正本（常時適用ルールのみ）
├── airules/             # 用途別ルール（該当時のみAIが読む）
│   ├── PITFALLS.md      # AI失敗パターン集（失敗のたびに追記して育てる）
│   ├── THINKING.md      # 実装時の思考規範（完了条件・影響範囲・検証経路の事前確定等）
│   ├── DESIGN.md        # 設計・実装計画
│   ├── WORKFLOW.md      # 分担作業フロー（Architect/Worker/Reviewer/Integrator）
│   ├── UNITY.md         # Unity実装
│   ├── UE5.md           # UE5実装
│   ├── GODOT.md         # Godot実装
│   ├── GAME_COMMON.md   # 共通モジュール設計（エンジン非依存）
│   ├── REVIEW.md        # コードレビュー（形式・観点）
│   └── GIT.md           # Git運用（PRレビューモード・init-ai-git確認含む）
├── Claude/
│   ├── CLAUDE.md        # Claude Code 固有の入口（AGENTS.mdをインポート）
│   └── agents/          # サブエージェント定義（architecture-reviewer / code-reviewer）
├── deploy.ps1           # ~/.codex・~/.claude へバックアップ付き配備
├── init-ai-git.ps1      # AI用SSH鍵をリポジトリへ設定（ユーザーが手動実行）
├── INSTALL.md           # セットアップ・MCP導入手順
└── PROGRESS.md          # 作業進捗
```

## 使い方

1. ルールを編集する（**正本はこのリポジトリ。配備先 `~/.codex`・`~/.claude` を直接編集しない**）
2. `.\deploy.ps1` を実行する
3. セットアップ詳細・MCP導入は [INSTALL.md](INSTALL.md) を参照

実行時にAIが読むのは配備先（`~/.codex`・`~/.claude`）のみで、このリポジトリの場所には依存しない。
**リポジトリを移動・改名した場合は、新しい場所で `deploy.ps1` を一度実行すること**（配備ファイルのヘッダーに埋め込まれるリポジトリへの案内パスが更新される）。

## 設計原則

- **AGENTS.md が正本**: 常に適用する共通方針のみを書く。Codexは `~/.codex/AGENTS.md` として全プロジェクトで自動読込、Claudeは `~/.claude/CLAUDE.md` からインポート
- **airules/ は条件付き**: 用途別に分割し、該当する作業のときだけAIが読む（コンテキスト節約）
- **ルール追加時の判断**: 常時適用なら AGENTS.md、条件付きなら airules/
- **役割分担（デフォルト）**: Codex = 実装・修正・差分整理、Claude = 設計・仕様整理・レビュー・Unity/UE/Godot作業補助
