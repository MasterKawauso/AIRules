# INSTALL — セットアップ

## 前提（2026-07-03確認）

Claude Code（`~/.claude`）、Codex CLI 0.142.0（`~/.codex`）、PowerShell 7を導入済み。

## 配備

ルール編集後、正本で実行する。

```powershell
cd D:\AIRules\AIRules
.\deploy.ps1
```

`InstallMCPElse.cmd`をダブルクリックすると、PM Skills・Unity公式ベータ版Unity CLI・UnityMCP・BlenderMCPを未導入時だけ導入する。配備処理は含まれない。PowerShellを新しく開いてから`unity --version`で確認する。個別に実行する場合は`installMCPElse.ps1 -Component UnityMcp`のように指定し、`-WhatIf`で変更内容を先に確認できる。

| 配備元 | 配備先/用途 |
|---|---|
| `Codex/AGENTS.md` | `~/.codex/AGENTS.md`（Codex自動読込） |
| `Codex/AGENTS.md` | `~/.claude/AGENTS.md`（参照先をSkill名へ変換して生成） |
| `Codex/airules/*.md` | `~/.codex/airules/` |
| `Codex/hooks/*.ps1` | `~/.codex/hooks/`と`~/.claude/hooks/`（共通ゲート） |
| `Codex/settings-hooks.json` | `~/.codex/hooks.json`へAIRules管理commandだけをマージ |
| `Codex/airules/*.md` | `~/.claude/skills/airules-*/SKILL.md`（frontmatter付きへ変換） |
| `Claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `Claude/agents/*.md` | `~/.claude/agents/` |
| `Claude/output-styles/*.md` | `~/.claude/output-styles/` |
| `Claude/hooks/*.ps1` | `~/.claude/hooks/` |

既存ファイルは`backup\<日時>\`へ保存する。旧`~/.claude/airules/`はSkill生成と検証が全て成功したあとにbackupへ退避してから削除する。検証に失敗した場合は旧`airules/`を残し、配備を完了扱いにしない。

`~/.claude/settings.json`と`~/.codex/hooks.json`はユーザー管理項目を保持し、AIRules管理commandとmatcherだけをマージする。既存の他Hook、設定、Skillsは削除しない。壊れたJSONや`hooks`がobjectでない設定では、書込み前に配備を停止する。

Codexは安定版hooks機能を使うため、`deploy.ps1`が既存`config.toml`を一時HOMEへ複製し、Codex CLI自身の`codex features enable hooks`と`codex features list`で読取検証後、`features.hooks=true`となった設定だけを配備する。Hook定義の新規・変更後はCodexのセキュリティ仕様により実行前の信頼確認が必要なので、次回起動時に`/hooks`で内容を確認して信頼する。Claude Codeは配備直後からマージ済みHookを使用する。

## Claude Skillの管理範囲

`deploy.ps1`は、`SKILL.md`の`AIRULES-MANAGED`マーカーと`~/.claude/airules-deployment-manifest.json`（前回の配備記録）で管理範囲を判定する。上書きと削除で条件が異なる。

- **上書き**はマーカーがあれば行う。マーカーはAIRulesが生成した証拠であり、配備記録は前回が完走したかしか示さないため。両方を要求すると、Skill配置後・記録確定前に中断した場合に以後の配備が拒否され続ける。記録が無くマーカーだけある場合は警告を出して採用する
- **削除**（孤児退避）はマーカーと配備記録の両方が揃う場合だけ行う。削除は復元しにくいため上書きより厳しくする
- 配備先のskill名にマーカーの無いSkillが既存していた場合、上書きも退避もせず配備全体を停止する
- PM Skills 9プラグイン、ユーザー独自Skill、プラグイン管理領域には触れない

## PM Skills（任意）

企画検証、市場性、競合、価格、販売戦略、PRD等には`phuryn/pm-skills`を使う。68 skills / 42 workflowsを9プラグインに分けたMITライセンスの公式Marketplaceで、内容はAIRules内へ複製しない。

CodexとClaude Codeへまとめて導入する。

```powershell
.\installMCPElse.ps1 -Component PmSkills
```

片方だけなら次を使う。

```powershell
.\installMCPElse.ps1 -Component PmSkills -Target Codex
.\installMCPElse.ps1 -Component PmSkills -Target Claude
```

導入対象は`pm-toolkit`、`pm-product-strategy`、`pm-product-discovery`、`pm-market-research`、`pm-data-analytics`、`pm-marketing-growth`、`pm-go-to-market`、`pm-execution`、`pm-ai-shipping`。Codexではskillsを名前または自然文で利用する。Claude固有のslash commandはCodexではslash commandとして実行されない。

更新時も同じスクリプトを再実行する。Marketplace CLIの仕様変更で失敗した場合は、原典READMEの最新手順を確認する。

## Unity CLI（InstallMCPElse.cmdで自動導入）

`InstallMCPElse.cmd`は、Unity公式の実験的CLIをbetaチャネルから未導入時のみ追加する。CLI単体はEditor/Module管理用で、起動中のEditorからGameObjectなどの最新状態を取得するには、対象Unityプロジェクトで次を一度実行する。

```powershell
cd <Unityプロジェクトのルート>
unity pipeline install
```

`com.unity.pipeline`はUnity 6.0 LTS以降で動作する実験的パッケージである。Editorを開いた状態で`unity command eval`などを使うため、対象プロジェクトを指定せずにdeployから自動追加はしない。CLIの更新は`unity upgrade`を使う。

## UnityMCP（InstallMCPElse.cmdで自動導入）

`CoplayDev/unity-mcp`（MCP for Unity）をCodexとClaude Codeへ`unityMCP`として登録する。BlenderMCPと同じく各CLIの`mcp add`を使い、Claudeには`--scope user`を付ける。

```powershell
.\installMCPElse.ps1 -Component UnityMcp
```

サーバ本体はPyPIの`mcpforunityserver`をuvxが実行時取得するため、`uv`が未導入なら登録せずスキップする。Unity側の導入はprojectごとの操作なので自動化せず、手順表示だけを行う。

- 対象projectのPackage Managerへ`https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity`を追加する
- `Window → MCP for Unity`で接続を確認する。同ウィンドウの`Configure All Detected Clients`でも登録できるが、その場合`uvx`が絶対パスで書かれるため、本スクリプトからは内容差分として停止扱いになる
- MCP経由でEditorのAsset・Sceneを変更できる。対象projectをGit管理下に置いてから使う

## BlenderMCP（InstallMCPElse.cmdで自動導入）

`ahujasid/blender-mcp`をCodexとClaude Codeへ登録する。設定ファイルを直接編集せず、各CLIの`mcp add`で登録する。Claudeは既定scopeがlocalのため`--scope user`を付ける。

```powershell
.\installMCPElse.ps1 -Component BlenderMcp
```

既に`blender`という名前のMCPが登録済みで内容が異なる場合は、上書きも削除もせず差分を表示して停止する。置換する場合だけ`-ReplaceExistingMcp`を付ける。変更前に`~/.codex/config.toml`と`~/.claude.json`を`%LOCALAPPDATA%\AIRules\backup\<日時>`へ保存する（機密が混じりうるためGit管理下には置かない）。

Blender側のAdd-on有効化と「Connect」はGUI操作のため自動化せず、手順表示だけを行う。BlenderMCPは任意コード実行機能とテレメトリ設定を持つため、用途を理解した上で使う。

## 初回移行（手動）

Codexはglobal→projectの`AGENTS.md`を後勝ち・合計32KiBで連結する。`deploy.ps1`は旧projectルールを検出しないため、各projectの旧`AGENTS.md`/`CodexSkills/`を確認する。

```powershell
Get-ChildItem D:\ -Directory -Depth 1 | ForEach-Object {
    Get-ChildItem $_.FullName -Include AGENTS.md,CodexSkills -Depth 1 -ErrorAction SilentlyContinue
}
```

旧共通ルールは削除し、project固有`AGENTS.md`は共通部分だけ除いて残す。

## Workflow選択の記録

同じ会話の回答は会話単位の一時状態として保持される。別セッションでも同じ作業単位の選択を引き継ぐ場合だけ、ユーザー承認後に`PLAN.md`または`SESSION.md`へ次の1行を置く。`scope`は現在作業を識別できる短い名前にする。

```text
AIRULES_WORKFLOW_SELECTION: owner=Codex; model=gpt-5.6-sol; thinking=medium; scope=認証API移行
```

3項目の欠落、未承認、別scopeの記録は無効。新しい会話でもscopeが一致する同一作業の実装・修正・検証・必要なレビューまで有効で、別作業には流用しない。機械ゲートに採用させるには、再開依頼に同じscope文字列を書くか、「`PLAN.md`の作業を再開」のように記録元を明示する。

## MCP（任意）

本仕組み自体はMCP非依存。`InstallMCPElse.cmd`が導入するのはクライアント側のMCP登録だけで、ルール配備には影響しない。

- Unity: `installMCPElse.ps1`がCodex/Claudeへ`unityMCP`（`uvx --from mcpforunityserver mcp-for-unity --transport stdio`）を登録する。サーバはuvxがPyPIから実行時取得するため`uv`が必須。Unity側は対象projectのPackage Managerで`https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity`を追加し、`Window → MCP for Unity`で接続を確認する
- Godot: Coding-Solo/godot-mcp等をclone/buildし、`claude mcp add godot -- node <path>/build/index.js`
- UE5: 2026年7月時点で公式版なし。`chongdashu/unreal-mcp`等は必要時に評価

同名で内容の異なるMCPが既に登録されている場合は差分を表示して停止する。上書きは`-ReplaceExistingMcp`の明示指定時だけ行い、直前に`%LOCALAPPDATA%\AIRules\backup\<日時>\`へ設定をバックアップする。Unity側のMCP for Unityウィンドウから設定した場合は`uvx`が絶対パスで登録されるため、内容が同等でも差分として停止することがある。

## 確認

Unity projectでCodexへ読了ルールとフェーズを尋ね、`UNITY.md`等が挙がることを確認する。Claudeでは`/airules-unity`等のSkillが読み込まれること、`/agents`にReviewerがあることを確認する。Skillの一覧と有効状態は`/skills`で確認できる。
