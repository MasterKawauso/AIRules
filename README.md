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

`workflow_gate.ps1`は、コード・ファイルを変更しない調査・質問回答・説明・設計・レビュー・差分確認と、対象ファイル・単一箇所・局所変更・禁止境界なしを依頼文から確認できる軽微な実装を除外し、実装・修正・実装委譲を行う作業で担当AI・モデル・思考深度が未選択なら変更ツールと実装委譲を停止する。「軽微」という自己申告だけでは除外しない。Codexは実行環境がセッションへ明示した現在設定を示し、推奨を1番にした2〜3個の番号付き候補として担当・モデル・思考深度、Worker使用有無、品質・費用・時間差を提示する。`config.toml`等の既定値やWorker起動時の指定値は現在値の根拠にせず、取得不能な項目は推測で補わない。ユーザーは「推奨」または`1`〜`3`だけで選択でき、「はい」「よい」「それで」「進めて」等の通常の承認も受理する。Codexで選択モデルまたは思考深度が親と異なる場合は、指定値のWorker起動を必須とし、親が切り替わったとは扱わない。選択待ちは現在の実変更依頼だけで強制し、途中の質問・説明・設計・レビュー・雑談やNode REPLによる読取調査では休止する。同じ作業単位の設計からレビューまでは同じ会話または承認済み`PLAN.md`/`SESSION.md`の選択を再利用する。

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
