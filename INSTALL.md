# INSTALL — セットアップ

## 前提（2026-07-03確認）

Claude Code（`~/.claude`）、Codex CLI 0.142.0（`~/.codex`）、PowerShell 7を導入済み。

## 配備

ルール編集後、正本で実行する。

```powershell
cd D:\AIRules\AIRules
.\deploy.ps1
```

| 配備元 | 配備先/用途 |
|---|---|
| `AGENTS.md` | 両環境の`AGENTS.md`（Codex自動読込、Claude import元） |
| `airules/*.md` | 両環境の`airules/` |
| `Claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `Claude/agents/*.md` | `~/.claude/agents/` |

既存ファイルは`backup\<日時>\`へ保存し、旧`~/.claude/skills/`の4ファイルは初回に退避する。

## PM Skills（deploy時に自動導入）

企画検証、市場性、競合、価格、販売戦略、PRD等には`phuryn/pm-skills`を使う。68 skills / 42 workflowsを9プラグインに分けたMITライセンスの公式Marketplaceで、内容はAIRules内へ複製しない。

CodexとClaude Codeへまとめて導入する。

```powershell
.\deploy.ps1
```

片方だけなら次を使う。

```powershell
.\install-pm-skills.ps1 -Target Codex
.\install-pm-skills.ps1 -Target Claude
```

導入対象は`pm-toolkit`、`pm-product-strategy`、`pm-product-discovery`、`pm-market-research`、`pm-data-analytics`、`pm-marketing-growth`、`pm-go-to-market`、`pm-execution`、`pm-ai-shipping`。Codexではskillsを名前または自然文で利用する。Claude固有のslash commandはCodexではslash commandとして実行されない。

更新時も同じスクリプトを再実行する。Marketplace CLIの仕様変更で失敗した場合は、原典READMEの最新手順を確認する。

## 初回移行（手動）

Codexはglobal→projectの`AGENTS.md`を後勝ち・合計32KiBで連結する。`deploy.ps1`は旧projectルールを検出しないため、各projectの旧`AGENTS.md`/`CodexSkills/`を確認する。

```powershell
Get-ChildItem D:\ -Directory -Depth 1 | ForEach-Object {
    Get-ChildItem $_.FullName -Include AGENTS.md,CodexSkills -Depth 1 -ErrorAction SilentlyContinue
}
```

旧共通ルールは削除し、project固有`AGENTS.md`は共通部分だけ除いて残す。

## Codex hook（任意・手動）

`~/.codex/hooks.json`に`PROGRESS.md`用hookはあるが無効。必要なら`config.toml`を変更する。deployは変更せず、常時ルールが同内容を補う。

```toml
[features]
hooks = true
```

## MCP（任意・未導入）

本仕組みはMCP非依存で、自動導入しない。

- Unity: Package Managerで`https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity`を追加し、`Window → MCP For Unity`から設定。手動時は画面の`claude mcp add`またはCodex `config.toml`へ同等設定を登録
- Godot: Coding-Solo/godot-mcp等をclone/buildし、`claude mcp add godot -- node <path>/build/index.js`
- UE5: 2026年7月時点で公式版なし。`chongdashu/unreal-mcp`等は必要時に評価

## 確認

Unity projectでCodex/Claudeへ読了ルールとフェーズを尋ね、`UNITY.md`等が挙がること、Claude `/agents`にReviewerがあることを確認する。
