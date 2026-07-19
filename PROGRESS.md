# PROGRESS

現在フェーズ: 本実装（ルール管理リポジトリのため参考値）

## 2026-07-19

- `backup/`を除く全Markdownを、適用条件・必須手順・禁止事項・例外を維持して圧縮。重複表現、冗長な説明、履歴内の重複経緯を統合

## 2026-07-15

- GitHub運用を`GITHUB.md`へ集約し、ローカル`ISSUE.md`を廃止。未移行課題「`deploy.ps1`のCursor配備」はGitHub Issue作成が必要
- Claude×Codexで全体レビューし、`WORKFLOW/GIT/REVIEW/GAME_COMMON/INSTALL/README`の矛盾・構成を修正
- `deploy.ps1`: 配備先`airules/`の余剰ファイルをバックアップ退避し、`agents/`・`output-styles/`の余剰を警告
- 旧記録「2026-07-04にCursor配備実装済み」は現行コードと不一致のため未実装へ訂正。作業残骸`repair_log.txt`を削除

## 2026-07-09

- `WORKFLOW.md`: Architect/Worker/Reviewer/Integratorによる設計→分割→並列実装→成果物別レビュー→統合→相互レビューを定義し、`AGENTS.md`・deploy変換メタへ接続
- `GIT.md`: main直接commit禁止、破壊操作禁止、push前確認、失敗時の`init-ai-git.ps1`確認、指示時限定のPRレビューモードを追加
- `Claude/CLAUDE.md`: 親がFableならSub AgentはSonnetとするモデル運用を追加
- 課題管理をローカル`ISSUE.md`からGitHub Issueへ移行。Cursor同期漏れとrebase/破壊操作ルールの矛盾を修正し、deploy実行

## 2026-07-05

- `THINKING.md`: 完了条件・影響範囲・検証経路、責務判断、デバッグ順序、検証基準、Editor操作・シリアライズ改名の規範を追加
- `AGENTS.md`とdeploy変換メタへ接続し、全環境へ配備

## 2026-07-04

- ツール既定動作より本ルールを優先すると明記。設計意図を薄めない、変更説明を短く段階化する等の実装フローを追加
- 全ルールを意味・条件・チェックリストを保って圧縮（`AGENTS.md`40%、他59〜87%。3割では情報欠落するため不採用）。`PROGRESS/README/INSTALL`は対象外
- Cursor用`core.mdc`を追加。当時はdeploy対応済みと記録したが、現行`deploy.ps1`にはなく未実装（2026-07-15訂正）

## 2026-07-03

- `AGENTS.md`を共通正本、`airules/`を用途別ルールとして再構成し、Codex/Claude間の重複・矛盾を解消
- モック期/本実装期、優先順位、必要ルールだけ読む方針、機能単位レビュー、進捗更新条件を定義
- Claude用`architecture-reviewer`/`code-reviewer`、`GODOT.md`、`PITFALLS.md`、`deploy.ps1`、`INSTALL.md`、`README.md`を追加
- `REVIEW.md`: 仕様単位判定、`REVIEW_STATE.md`による差分限定、実害のない好み指摘禁止を追加
- `UNITY.md`: AIが扱いやすいファイル/クラス、Pure C#、フィーチャー別配置、asmdef、薄いScene/Prefab方針を追加
- `GAME_COMMON.md`と`REVIEW.md`を全ゲーム実装・完了報告へ適用し、参照ルールを完了報告項目に追加
- 旧`Codex/`・`Claude/skills/`・`Claude/hooks/`を統合後に削除し、`~/.codex`・`~/.claude`へ配備
