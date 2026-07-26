# AIRules

Codex CLI/Claude Code共通ルールの正本と、バックアップ付き配備スクリプト。

## 構成

```text
Codex/                    ルール本文の唯一の正本（Codex/Claude共通）
  AGENTS.md               常時ルール
  airules/                条件別ルール
    REQUIREMENTS/THINKING/PITFALLS/DESIGN/WORKFLOW.md
    UNITY/UE5/GODOT/GAME_COMMON.md
    REVIEW/GIT/GITHUB.md
Claude/                   Claude固有物と変換定義
  CLAUDE.md               Claude Code入口
  skills/manifest.json    Skill化のdescription定義
  agents/                 要件・設計・コードReviewer
  output-styles/          出力Style
  hooks/                  Claude固有Hook
Codex/hooks/              両AIへ配備する共通workflow gate
Codex/settings-hooks.json Codex Hook登録定義
deploy.ps1                AIRulesの配備
installMCPElse.ps1        PM Skills・Unity CLI・UnityMCP・BlenderMCPの導入
InstallMCPElse.cmd        上記のダブルクリック用ランチャー
init-ai-git.ps1           AI用SSH設定（手動実行）
INSTALL.md / PROGRESS.md  Setup / 履歴
```

ルール本文は`Codex/`だけに置き、Claude用は`deploy.ps1`が変換して生成する。同じルールを二重管理しない。

## 使い方

1. このリポジトリを編集する（配備先`~/.codex`・`~/.claude`は直接編集しない）
2. `./deploy.ps1`でAIRulesを配備する
3. 必要に応じて`InstallMCPElse.cmd`を実行し、PM Skills・Unity CLI・UnityMCP・BlenderMCPを導入する
4. 詳細とMCPは[INSTALL.md](INSTALL.md)を参照する

AIは配備先を読む。リポジトリ移動・改名後は、生成ヘッダーの正本パス更新のため新しい場所で再配備する。

`workflow_gate.ps1`は、複雑・高リスク作業を複合条件で分類し、担当AI・モデル・思考深度が未選択なら変更ツールと委譲を停止する。読取調査と軽微な単発修正は通し、同じ会話または承認済み`PLAN.md`/`SESSION.md`の選択を再利用する。

## Codexへの配備

`Codex/AGENTS.md`と`Codex/airules/*.md`をそのまま`~/.codex/`へ配備する。Codexは`AGENTS.md`の条件付きルール表を見て、必要な`airules/`の文書だけを読む。配備時は既存`~/.codex/hooks.json`を保持マージし、Codex CLI自身で`features.hooks=true`を安全に有効化する。変更されたユーザーHookはCodexの`/hooks`で信頼確認が必要になる。

## ClaudeへのSkill化配備

条件別ルール12本は`~/.claude/skills/airules-*/SKILL.md`へ変換して配備する。descriptionを見たClaudeが該当作業時に自動で読み込むため、`~/.claude/airules/`は使わない。

- skill名はファイル名から自動生成する（`GAME_COMMON.md` → `airules-game-common`）
- descriptionは`Claude/skills/manifest.json`の定義を使う。未登録なら本文冒頭から自動導出し、警告を出す
- 本文は無改変で連結する。ただしルール間の相互参照（`` `REQUIREMENTS.md` ``等）だけは、Claude環境に該当ファイルが無いためSkill参照へ機械変換する
- 生成物には`AIRULES-MANAGED`マーカーを付ける。上書きはマーカーを持つものだけ、削除（孤児退避）はマーカーと配備記録が揃うものだけに限定する。PM Skillsやユーザー独自Skillには触れない（詳細は[INSTALL.md](INSTALL.md)）

### 新しいルールを追加するとき

`Codex/airules/`へmdを置くだけでよい。deployがskill名とdescriptionを自動生成する。自動導出のdescriptionは適用条件の見出し文になりトリガとして弱いため、運用するものは`Claude/skills/manifest.json`へ「いつ使うか」を先頭に書いたdescriptionを追記する。

## PM Skills

企画検証、市場性、競合、価格、GTM、PRD等には[phuryn/pm-skills](https://github.com/phuryn/pm-skills)を利用する。内容はAIRulesへ複製せず、公式MarketplaceからCodex/Claudeへ導入・更新する。
