# PROGRESS

現在フェーズ: 本実装（ルール管理リポジトリのため参考値）

## 2026-07-27

- Workflow選択ゲートを、コード・ファイルの実変更を伴う実装・修正・実装委譲だけで発火する境界へ変更。調査・質問回答・説明・相談・設計・レビュー・差分確認だけでは発火せず、実装語を含む相談や否定文も除外し、レビュー後に修正する依頼や短い実変更指示は対象とした
- 推奨後の「はい」「よい」「それで」「進めて」や「今のモデルで進めて」を選択として受理し、定型文・ラベル付き回答を不要化。選択待ちは現在の実変更依頼だけで強制し、途中の非実装会話では休止、実変更へ戻ると再開するschema 2へ更新して旧pendingを自動無効化した。Node REPLは呼出内容を検査し、読取系ツールだけを通す
- Codexの推奨には現在のモデル・思考深度設定を併記し、ユーザー選択が親と異なる場合は指定値のWorkerへ実装を任せる。実行中設定を取得不能なら`config.toml`既定値と明記し、Workerで指定モデルを利用不能なら勝手に代替せず確認する
- モデル確認を省略できる軽微実装を、対象が既存実装1ファイル＋直接テスト1つ以内、単一箇所の誤字・文言・コメント・import・定数・比較演算子・条件式・Nullチェック、禁止境界なしを依頼文から確認できる場合に限定。「軽微」の自己申告、Public API・設定、新規ファイル、実装2ファイルは拒否。上記の状態遷移・自然な承認・非実装除外・Node REPL判定を含む49ケースを一時HOMEで検証し全件成功

## 2026-07-26

- 担当AI・モデル・思考深度の確認が守られなかった根本原因を、常時読込の`AGENTS.md`から遅延発火Skillへ判定を委ね、親AIの着手を止める状態・Hookがなく、既存Hookもmodel未指定Sub Agentだけを対象にしていた構造と特定。`AGENTS.md`へ客観的な開始判定を置き、`WORKFLOW.md`で高リスク変更・設計判断・複数責務・委譲を独立条件化した
- Claude/Codex共用の`workflow_gate.ps1`をUserPromptSubmit・PreToolUse・Stopへ登録。作業単位の選択状態を保持し、未選択の変更・委譲をPreToolUseで停止、推奨案を出さず終了する応答をStopで差し戻す。明示指定、同一会話の回答、`PLAN.md`/`SESSION.md`の構造化選択は再利用し、別作業の明示で失効、Explore等の読取専用は除外した。解析不能入力はfail open、要確認状態での変更系ツールはfail closed
- `deploy.ps1`はClaude/Codex双方の既存Hookをマージ保持し、Codexのstable hooks機能をCLIで有効化する。管理マーカーまたは既知の旧版hashがない同名Hookは上書きせず、破損JSON・不正TOML・Hook配置失敗では設定切替前に停止する。正本は`Codex/`のままClaude用`AGENTS.md`と`airules-workflow` Skillを生成する
- 一時HOMEで25ケースを検証し全件成功: 軽微修正、設計/複数責務/Public API、明示指定/同一会話/PLAN再利用、別作業失効、Sub Agent model有無、Explore、Stop、既存設定保持、二重配備、配置不能、同名衝突、破損JSON、想定外payload。別AIレビューで見つかった設計語だけの依頼・早すぎる短文承認・同名Hook上書き・設定先行切替の4点も修正し、実環境配備物の本文・hash・3イベント登録・Codex hooks有効化を確認した
- 既知の限界: 自然文分類には誤検知/見逃しが残り、Hookを無効化・未信頼にした環境、Hook対象外の専用実行経路、ツール前の内部思考だけは機械停止できない。常時読込ゲートと構造化選択記録を代替線とし、Codexでは新規/変更Hookをセッション開始後に`/hooks`で信頼確認する必要がある
- `deploy.ps1`が`Claude/settings-hooks.json`を正本として`~/.claude/settings.json`のPreToolUse（Agent）/UserPromptSubmit/Stopをマージ管理するようにした（Codex実装、Claudeレビュー）。hookファイルは配備されるのに登録だけ手動で、環境再構築時に防止線が黙って無効化される穴を閉じた
- 設定の読取・マージはtry先頭で行い、書込みはSkill配備後まで遅延させる。破損JSONやマージ不能な形状は書込み前にthrowさせ、ユーザー設定を失わないため
- AIRules管理hookの同一判定はcommand文字列で行い、既存エントリから同一commandだけを除去して再追加する。matcherは判定に使っていないため、同一commandを別matcherで登録している場合はmatcherがAIRules定義側へ寄せられる。現状該当なしだが、将来同じスクリプトを複数matcherで使うなら判定条件の見直しが必要
- `Write-Error`が`$ErrorActionPreference='Stop'`で自身を例外化し、失敗時に`exit 1`へ到達せず終了コード0を返していた既存不具合を`-ErrorAction Continue`で修正。呼び出し側が配備失敗を検知できない状態だった
- 検証: native Windowsパスの一時`-HomeDirectory`で(a)新規作成 (b)無関係設定+ユーザー独自hookへのマージ (c)2回実行の冪等性 (d)破損JSONでexit 1・ファイル無変更、を確認。実環境配備後もキー欠落0件・hook以外の設定変更0件、Agentゲートの発火を再確認。Git Bash経由では`-HomeDirectory`のパスが書き換わり検証が偽陽性になるため、PowerShellから実行する必要がある
- model未指定のSub Agent起動事故（`WORKFLOW.md`の確認ゲートを読まずに最高モデルで実行しトークン超過）の再発防止に、PreToolUse hook `Claude/hooks/require_agent_model.ps1`を追加。`Agent`ツールの`tool_input.model`が空なら`permissionDecision=deny`で停止する。過去ログ上のAgent起動14件はすべて`model`を渡しておらず、省略時は親モデル(opus)を継承するため事故が機械的に起きる構造だった
- 読取専用・軽量な`Explore`/`statusline-setup`/`claude-code-guide`と、`model`明示済みの起動は通す。payload不正・空入力はfail openとし、通常作業を妨げない方針にした
- 拒否理由に是正手順（ユーザー確認を待つ／`model`を明示して再実行／調査なら`Explore`）を含め、停止で終わらず次の行動が決まるようにした
- `Claude/hooks/`が`deploy.ps1`の管理対象として定義済みだが実体が未取り込みだったため、既存の`read_progress.ps1`・`remind_progress.ps1`もリポジトリへ取り込み配備管理下にした
- 検証: 単体5パターン（model無/有・Explore・他ツール・空入力）と実ハーネスでの拒否・許可の両方を確認。`deploy.ps1`実行で配備物一致を確認。`settings.json`への`PreToolUse`登録は手動追加（deploy管理外）
- `installMCPElse.ps1`へ`CoplayDev/unity-mcp`（MCP for Unity）導入を追加。`-Component UnityMcp`を新設し、既定の`All`にも組み込んだ。Codex/Claudeへ`unityMCP`を`uvx --from mcpforunityserver mcp-for-unity --transport stdio`で登録し、uvx未導入時はサーバが起動できないためスキップする
- BlenderMCP用の登録処理を汎用化して共用（`Install-BlenderMcpForClient`→`Install-McpForClient`、`Test-BlenderMcpConfiguration`→`Test-McpConfiguration`）。既存差異時の停止・`-ReplaceExistingMcp`・設定バックアップの方針は両MCPで共通のままとした
- 設定一致判定は期待コマンドとargsトークン列を引数化し、args全体を空白1個区切りで比較する。部分一致だと`--from`のパッケージ名違いや`--transport`欠落を同一と誤判定するため。Unity側ウィンドウが書く絶対パス`uvx.exe`は差分として停止扱いになることを`INSTALL.md`に明記
- Unity package追加とEditor接続確認はproject単位のGUI操作のため自動化せず手順表示のみ。`INSTALL.md`のMCP節を「未導入」から実態へ更新し、`README.md`の記載も合わせた
- `InstallMCPElse.cmd`が常に「pwshが見つかりません」で終了していた原因は2つ。(1)改行がLFのみで`cmd.exe`が行を途中で切り、断片を別コマンドとして解釈していた (2)`if`ブロック内`echo`の`(pwsh)`が未エスケープでブロックを早期終了させていた。CRLF化と`^(`/`^)`エスケープで修正し、ダブルクリック起動が通ることを実行確認した
- 同じ事故の再発防止に`.gitattributes`を追加し、`*.cmd`/`*.bat`/`*.ps1`を`eol=crlf`で固定した（未コミット）

## 2026-07-25

- ルール本文の正本を`Codex/`へ集約し、`AGENTS.md`と`airules/*.md` 12本を本文無改変のまま移動。Claude側は本文を複製せず`deploy.ps1`が変換生成する単一ソース構成にした
- Claudeの条件別ルールを`~/.claude/skills/airules-*/SKILL.md`へSkill化し、`~/.claude/airules/`を廃止。descriptionによる自動発火に任せ、CLAUDE.mdへの強制読込指示は入れない方針を採用
- skill名はファイル名から自動生成、descriptionは`Claude/skills/manifest.json`優先・未登録時は本文冒頭から自動導出。新規md追加は`Codex/airules/`へ置くだけで配備が通る。自動導出は適用条件の見出し文でトリガが弱いため、運用中の12本は手書きdescriptionを正とした
- 配備物の本文中のルール相互参照をSkill参照へ機械変換。バッククォート囲みの完全一致トークンだけを対象とし、同一文書で3箇所以上変換した場合は巻き込みの可能性として警告する
- Claude用`AGENTS.md`の表変換は期待出現数を検査し、不一致なら無変更で失敗させる。変換後に未変換の`.md`参照が表へ残っていた場合も、変換定義の更新漏れとして失敗させる
- Skillの管理境界を、上書きは`AIRULES-MANAGED`マーカー、削除（孤児退避）はマーカー＋配備記録の二条件と非対称にした。両方要求すると記録確定前の中断で以後の配備が拒否され続けるため。マーカーはfrontmatter直後の行にあり書式が一致するものだけを有効とし、マーカーの無いSkillと名前衝突した場合は配備全体を停止する。PM Skills・ユーザー独自Skillには触れない
- `Cursor/core.mdc`を廃止。`~/.claude/hooks/`の2ファイルを`Claude/hooks/`へ取り込み配備管理下にした
- `install-pm-skills.ps1`と`install-unity-cli.ps1`を`installMCPElse.ps1`へ統合し、BlenderMCP導入を追加。CLI経由登録・既存差異時の停止・`%LOCALAPPDATA%`へのバックアップとし、`InstallMCPElse.cmd`はpwsh前提の薄いランチャーにした
- `WORKFLOW.md`の担当AI・モデル・思考深度確認を客観条件と着手前の停止ゲートに変更。複数責務、エンジン設定、Public API等を含む場合は回答を待ち、既定担当を確認省略の根拠にできないことを明記

## 2026-07-24

- `deploy.ps1`からPM Skillsの確認・導入を外し、AIRulesの配備専用に変更
- 配備処理を含む`deploy.cmd`を廃止し、PM SkillsとUnity公式beta版Unity CLIだけを未導入時に導入する`InstallMCPElse.cmd`へ置換。対象Unityプロジェクトへの`com.unity.pipeline`追加手順を`INSTALL.md`へ記載
- `UNITY.md`へ、CLI/Pipeline利用可否を先に検査し、未導入の`com.unity.pipeline`追加は明示許可後だけ`unity pipeline install`を実行するフローを追加

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
