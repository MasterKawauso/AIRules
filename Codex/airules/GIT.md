# GIT — Git運用

Gitの変更操作（commit/branch/push等）時に適用。状態・差分の読取だけなら必要部分のみ適用する。

## 通常

- 1コミット1機能。一塊の機能変更・追加作業が完了するごとに、変更を長く溜めずこまめにcommitする。機能追加と大規模リファクタを混ぜず、指示外ファイルを含めない
- 作業前にブランチを確認し、main/masterへのcommit・変更はユーザー指示時だけ行う
- commit前にコンパイルエラー、不要変更、デバッグコード、意図しないTODO・コメント変更を、push前に差分・テスト・競合を確認する。失敗・競合時はpush/PRを止めて報告する
- rebase、`reset --hard`、`git clean`、revert、force push、branch/tag削除、履歴書換えは許可なく実行しない（既定のworktree・PRレビューフローで作業branchへmainを取り込む場合を除く）
- 変更操作前に内容と影響を一度説明する。連続する同目的の操作はまとめ、同じ説明を繰り返さない
- 根本的に別の修正を指示された場合、未マージ作業があれば別branchにする
-  コミットメッセージは日本語

## 並行Agent

1 Agent=1 worktree=1 branch。他Agentのworktree/branchや親リポジトリを変更・checkoutせず、Integratorが統合する。同じ作業ディレクトリでbranchを切り替えず、原則mainを握らない。worktree作成・削除失敗時は停止・報告する。
***大事なこと***
親ブランチを絶対に切り替えないこと。ユーザーが作業をしている

## 失敗時

push/PRの認証・SSH設定が疑われる失敗では、再試行前に`init-ai-git.ps1`実行済みか確認する。未実行ならユーザーへ依頼する。ユーザー管理スクリプトのためAIは作成・探索・自動実行しない。

## 既定のworktree・PRレビューフロー

Git管理下の実変更は、ユーザーの明示がなくても最新main取得→作業worktree・branch作成→実装→必要ならmain取込み→テスト→commit→push→PR作成→通知の順で行う。PR・Issueは`GITHUB.md`に従う。

ユーザーが「直コミットで」「PR不要」「現在のbranchへ直接commit」等、worktreeまたはPRを使わない方針を現在の作業へ明示した場合だけ、その指定範囲では本フローを省略する。過去の作業への例外指示を別作業へ引き継がない。main/masterへのcommit・変更は、上記とは別にユーザーの明示を必要とする。
