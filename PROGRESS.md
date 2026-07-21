# PROGRESS

現在フェーズ: 本実装（ルール管理リポジトリのため参考値）

## 2026-07-21

- `deploy.cmd` 経由のPM Skills導入で、Codex/Claudeそれぞれの導入済み一覧を確認し、9プラグインがすべて導入済みならMarketplace登録・導入をスキップするようにした
- 実行ポリシーを変更せずダブルクリックで配備できる`deploy.cmd`を追加。PowerShell 7を優先し、未導入時はWindows PowerShellへフォールバックする
- `phuryn/pm-skills`を公式Marketplace経由でCodex/Claudeへ導入する`install-pm-skills.ps1`を追加。`deploy.ps1`の通常実行から9プラグインを自動確認・導入するようにした
- 企画検証・市場性・価格・販売戦略・プロダクト判断では、独自記事を追加せず導入済みPM Skillsを参照する導線を`AGENTS.md`へ追加

## 2026-07-19

- `backup/`外の全Markdownを、適用条件・安全確認・禁止・例外を維持して圧縮。読み込み量に加え、再読、全観点出力、軽微作業での設計確認・委譲・複数/相互レビュー等を条件化して実行時トークンを削減
- `WORKFLOW.md`に、長い会話を安全な区切りで`SESSION.md`へ要約し、ユーザーへ新セッションへの切替を促す引継ぎフローを追加

## 2026-07-15

- GitHub運用を`GITHUB.md`へ集約し`ISSUE.md`を廃止。`WORKFLOW/GIT/REVIEW/GAME_COMMON/INSTALL/README`の矛盾をClaude×Codexで修正
- `deploy.ps1`へ配備先`airules/`余剰ファイルのbackup退避と、`agents/`・`output-styles/`余剰警告を追加
- 2026-07-04のCursor配備済み記録を現行コードに合わせ未実装へ訂正し、`repair_log.txt`を削除。未移行課題はGitHub Issue作成が必要

## 2026-07-09

- `WORKFLOW.md`へArchitect/Worker/Reviewer/Integratorの設計→分割→並列実装→成果物レビュー→統合→相互レビューを定義
- `GIT.md`へmain直接commit・破壊操作の禁止、push前確認、`init-ai-git.ps1`確認、明示時限定PRレビューモードを追加
- Claude親Fable時のSub Agent=Sonnet運用、課題のGitHub Issue移行、Cursor同期漏れとrebase規則の矛盾修正を配備

## 2026-07-05

- `THINKING.md`へ完了条件、影響・検証経路、責務判断、デバッグ順、Editor操作、serialize改名規範を追加して全環境へ配備

## 2026-07-04

- ツール既定より本ルールを優先し、設計意図維持・短い段階報告等を追加。意味と条件を保ち全ルールを圧縮（`AGENTS.md`40%、他59〜87%、3割案は情報欠落で不採用）
- Cursor用`core.mdc`を追加。当時のdeploy対応済み記録は2026-07-15に訂正

## 2026-07-03

- `AGENTS.md`を正本、`airules/`を条件別ルールに再編し、役割・優先順位・開発フェーズ・必要文書だけ読む方針・機能単位review・`REVIEW_STATE.md`・進捗更新を定義
- Reviewer、Godot/Pitfalls/Game共通/Review/GitHub規則、deploy/setup文書を追加。UnityのAI向け構成、Pure C#、feature配置、asmdef、薄いScene/Prefab方針を整備
- 旧`Codex/`・`Claude/skills/`・`Claude/hooks/`を統合後削除し、両環境へ配備
