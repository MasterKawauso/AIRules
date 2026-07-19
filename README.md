# AIRules

Codex CLI/Claude Code共通ルールの正本と、バックアップ付き配備スクリプト。

## 構成

```text
AGENTS.md                 常時ルールの正本
airules/                  条件別ルール
  REQUIREMENTS/THINKING/PITFALLS/DESIGN/WORKFLOW.md
  UNITY/UE5/GODOT/GAME_COMMON.md
  REVIEW/GIT/GITHUB.md
Claude/CLAUDE.md          Claude Code入口
Claude/agents/            要件・設計・コードReviewer
Claude/output-styles/     出力Style
Cursor/core.mdc           Cursor用（deploy未対応、手動配置）
deploy.ps1                配備
init-ai-git.ps1           AI用SSH設定（手動実行）
INSTALL.md / PROGRESS.md  Setup / 履歴
```

## 使い方

1. このリポジトリを編集する（配備先`~/.codex`・`~/.claude`は直接編集しない）
2. `.\deploy.ps1`を実行する
3. 詳細とMCPは[INSTALL.md](INSTALL.md)を参照する

AIは配備先を読む。リポジトリ移動・改名後は、生成ヘッダーの正本パス更新のため新しい場所で再配備する。

常時ルールは`AGENTS.md`、条件付きルールは`airules/`へ置く。Claudeは`CLAUDE.md`から正本を読み、既定ではCodexが実装・修正・差分、Claudeが設計・仕様・レビュー・ゲームエンジン補助を担当する。
