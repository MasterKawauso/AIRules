# INSTALL — セットアップ手順

## 0. 前提環境（2026-07-03 確認済み）

| 項目 | 状態 |
|---|---|
| Claude Code | 導入済み（`~/.claude`） |
| Codex CLI | 導入済み（0.142.0 / `~/.codex`） |
| PowerShell 7 | 導入済み |

## 1. ルールの配備（基本操作）

リポジトリのルールを編集したら、毎回これを実行するだけ。

```powershell
cd D:\AIRules\AIRules
.\deploy.ps1
```

| 配備元 | 配備先 | 用途 |
|---|---|---|
| `AGENTS.md` | `~/.codex/AGENTS.md` | Codexが全プロジェクトで自動読込（グローバル） |
| `AGENTS.md` | `~/.claude/AGENTS.md` | CLAUDE.md からインポートされる正本 |
| `airules/*.md` | `~/.codex/airules/`・`~/.claude/airules/` | 条件付きルール（該当時のみAIが読む） |
| `Claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude Code グローバル入口 |
| `Claude/agents/*.md` | `~/.claude/agents/` | サブエージェント定義 |

- 既存ファイルは `backup\<日時>\` へ自動バックアップされる
- 旧 `~/.claude/skills/` の4ファイル（unity.md 等）は初回実行時にバックアップへ退避される

## 2. 初回移行チェック（重要・手動）

Codexは「グローバル `~/.codex/AGENTS.md` → プロジェクトの `AGENTS.md`」の順で**連結**して読む（後勝ち・合計32KiB上限）。
そのため、過去に各プロジェクトへコピーした旧 `AGENTS.md` / `CodexSkills/` が残っていると、**古い矛盾したルールが新ルールを上書きする**。

`deploy.ps1` 実行時に既知プロジェクトの検出結果が表示されるので、以下の方針で整理する。

- 旧共通ルールのコピー（`CodexSkills/`・旧共通 `AGENTS.md`）→ 削除
- プロジェクト固有の仕様が書かれた `AGENTS.md` → 残してよい（共通ルール部分だけ削る）

## 3. Codexフックの有効化（任意・手動）

`~/.codex/hooks.json` に PROGRESS.md 用フック（session_start / stop）が設定済みだが、
`~/.codex/config.toml` で機能自体が無効になっている。

```toml
[features]
hooks = false   # ← true にすると有効
```

意図的に無効化した可能性があるため、deploy では自動変更していない。有効化する場合は手動で `true` に変更する。
（AGENTS.md の「セッション開始時」ルールが同じ内容をカバーしているため、無効のままでも運用は成立する）

## 4. MCPサーバー導入（任意・未実行・当面導入しない方針）

**本リポジトリの仕組み（AGENTS.md / airules / サブエージェント / フック）はMCPに一切依存しない。MCP未導入のままで全機能が動作する。**
UnityがMCP導入に厳しくなったため、当面はMCPなしの環境を維持する方針。以下は将来必要になった場合の参考手順。
（エディタ側へのプラグイン/パッケージ導入がプロジェクトごとに必要なため、このリポジトリからは自動実行していない）

### Unity — MCP for Unity（CoplayDev/unity-mcp を推奨）

1. Unity Package Manager → `Add package from git URL`:
   `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity`
2. Unityメニュー `Window → MCP For Unity` を開き、使用クライアント（Claude Code / Codex）を選んで自動セットアップ
3. 手動登録する場合:
   - Claude Code: MCP For Unity ウィンドウに表示される `claude mcp add` コマンドを実行
   - Codex: `~/.codex/config.toml` の `[mcp_servers.<name>]` に同等のコマンドを登録

### Godot — godot-mcp（Coding-Solo/godot-mcp 等）

- Node.js製MCPサーバー。リポジトリをcloneしてビルド後、`claude mcp add godot -- node <path>/build/index.js` で登録（詳細は各リポジトリのREADME参照）

### UE5 — コミュニティ製（実験的）

- 2026年7月時点で公式MCPサーバーはない。`chongdashu/unreal-mcp` 等のコミュニティ製が存在するが実験的。必要になった時点で評価して導入する

## 5. 動作確認

1. 任意のUnityプロジェクトで `codex` を起動し「読んだルールとフェーズ認識を一行で報告して」と依頼 → airules/UNITY.md 等が挙がるか
2. 同プロジェクトで `claude` を起動 → 同様に確認。`/agents` で `architecture-reviewer` / `code-reviewer` が表示されるか
