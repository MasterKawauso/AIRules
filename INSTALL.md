# INSTALL — セットアップ手順

## 0. 前提（2026-07-03確認）

| 項目 | 状態 |
|---|---|
| Claude Code | 導入済み（`~/.claude`） |
| Codex CLI | 導入済み（0.142.0 / `~/.codex`） |
| PowerShell 7 | 導入済み |

## 1. 配備

ルール編集後に実行する。

```powershell
cd D:\AIRules\AIRules
.\deploy.ps1
```

| 配備元 | 配備先 | 用途 |
|---|---|---|
| `AGENTS.md` | `~/.codex/AGENTS.md`, `~/.claude/AGENTS.md` | Codex自動読込/Claude import元 |
| `airules/*.md` | 両環境の`airules/` | 条件付きルール |
| `Claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude入口 |
| `Claude/agents/*.md` | `~/.claude/agents/` | Agent定義 |

- 既存ファイルは`backup\<日時>\`へ保存。旧`~/.claude/skills/`の4ファイルは初回に退避する

## 2. 初回移行チェック（重要・手動）

Codexはグローバル→プロジェクトの`AGENTS.md`を連結する（後勝ち、合計32KiB）。旧`AGENTS.md`/`CodexSkills/`が残ると古い規則が上書きする。

`deploy.ps1`は検出しないため各プロジェクトを手動確認する。

```powershell
# 例: プロジェクト置き場を検索（パスは自分の環境に合わせる）
Get-ChildItem D:\ -Directory -Depth 1 | ForEach-Object {
    Get-ChildItem $_.FullName -Include AGENTS.md,CodexSkills -Depth 1 -ErrorAction SilentlyContinue
}
```

- 旧共通ルール（`CodexSkills/`・旧共通`AGENTS.md`）は削除
- 固有仕様の`AGENTS.md`は共通部分だけ削除して残す

## 3. Codexフックの有効化（任意・手動）

`~/.codex/hooks.json`に`PROGRESS.md`用フックはあるが、`config.toml`では無効。

```toml
[features]
hooks = false   # ← true にすると有効
```

deployは変更しない。有効化は手動で`true`にする。`AGENTS.md`が同内容を補うため無効でも運用可能。

## 4. MCP（任意・未導入）

本仕組みはMCP非依存。当面は導入せず、以下は将来用。エディタ側導入がプロジェクトごとに必要なため自動化しない。

### Unity（CoplayDev/unity-mcp推奨）

1. Unity Package Manager → `Add package from git URL`:
   `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity`
2. `Window → MCP For Unity`でクライアントを選びセットアップ
3. 手動登録する場合:
   - Claude: 画面表示の`claude mcp add`を実行
   - Codex: `config.toml`の`[mcp_servers.<name>]`へ同等コマンドを登録

### Godot — godot-mcp（Coding-Solo/godot-mcp 等）

- Node.jsサーバーをclone・buildし、`claude mcp add godot -- node <path>/build/index.js`（詳細は配布元README）

### UE5 — コミュニティ製（実験的）

- 2026年7月時点で公式版なし。`chongdashu/unreal-mcp`等は実験的なため必要時に評価する

## 5. 動作確認

1. Unityプロジェクトの`codex`へ読了ルールとフェーズを尋ね、`UNITY.md`等が挙がるか確認
2. `claude`でも確認し、`/agents`に両Reviewerがあるか確認
