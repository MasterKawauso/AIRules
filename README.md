# AIRules

Codex CLI/Claude Code共通ルールの正本と配備スクリプト。

## 構成

```
AIRules/
├── AGENTS.md            # 共通方針の正本（常時適用ルールのみ）
├── airules/             # 用途別ルール（該当時のみAIが読む）
│   ├── PITFALLS.md      # AI失敗パターン
│   ├── THINKING.md      # 思考規範
│   ├── DESIGN.md        # 設計・実装計画
│   ├── WORKFLOW.md      # 分担作業フロー
│   ├── UNITY.md         # Unity実装
│   ├── UE5.md           # UE5実装
│   ├── GODOT.md         # Godot実装
│   ├── GAME_COMMON.md   # エンジン共通設計
│   ├── REVIEW.md        # レビュー
│   ├── GIT.md           # Git運用
│   └── GITHUB.md        # GitHub運用
├── Claude/
│   ├── CLAUDE.md        # Claude Code入口
│   ├── agents/          # レビューAgent
│   └── output-styles/   # 出力スタイル
├── Cursor/core.mdc      # Cursor用（deploy未対応、手動配置）
├── deploy.ps1           # バックアップ付き配備
├── init-ai-git.ps1      # AI用SSH設定（手動実行）
├── INSTALL.md           # セットアップ
└── PROGRESS.md          # 作業進捗
```

## 使い方

1. このリポジトリのルールを編集する（配備先`~/.codex`・`~/.claude`は直接編集しない）
2. `.\deploy.ps1` を実行する
3. セットアップ詳細・MCP導入は [INSTALL.md](INSTALL.md) を参照

AIは配備先だけを読む。リポジトリ移動・改名後は、ヘッダーの正本パスを更新するため新しい場所で`deploy.ps1`を実行する。

## 設計原則

- `AGENTS.md`: 常時方針。Codexが自動読込し、Claudeは`CLAUDE.md`からimport
- `airules/`: 作業条件別ルール。該当時だけ読む
- 新規ルールは常時なら`AGENTS.md`、条件付きなら`airules/`
- 既定担当: Codex=実装・修正・差分、Claude=設計・仕様・レビュー・ゲームエンジン補助
