# GIT — Git運用ルール

Git操作（commit/branch/push等）時に適用。

## 通常ルール

- 1コミット1機能。機能追加と大規模リファクタを混ぜず、指示外ファイルを含めない
- 作業前にブランチを確認する。main/masterへのcommit・変更はユーザー指示時だけ
- commit前にコンパイルエラー、不要変更、デバッグコード、意図しないTODO・コメント変更を確認する
- push前に差分を確認する。テスト失敗・競合時はpush/PR作成を停止し報告する
- rebase/reset --hard/git clean/revert/force push/branch・tag削除/履歴書換えは許可なく行わず提案だけする。ただしPRレビューモードで作業ブランチへmainを取り込む場合を除く
- 実行前に内容と影響範囲を簡潔に説明する
- ユーザーから根本的に別問題の修正が指示された場合、未マージの作業があっても別のブランチを作成する

## 並行Agent用Gitルール

同時作業時はAgentごとに`git worktree`とbranchを分け、同じ作業ディレクトリでbranchを切り替えない。

- 1 Agent = 1 worktree = 1 branch
- 他Agentのworktree/branchや親リポジトリを変更・checkoutしない
- Integratorが成果物を統合する。worktree作成・削除失敗時は停止・報告する
- 原則としてmainブランチを握らない

## Git操作に失敗したら

commit/push/PR作成失敗時は原因調査前に「`init-ai-git.ps1`を実行済みですか？」と確認する。未実行なら依頼後に再試行する。ユーザー管理スクリプトのためAIは作成・探索・自動実行しない。

## PRレビューモード

「PRレビューモード」「PRレビューで」「PRフローで」の指示時だけ有効。

最新main取得→作業worktree作成→実装→必要ならmain取込み（merge/rebase）→テスト→commit→push→PR作成→通知。

PR作成・レビューとGitHub Issue管理はGITHUB.mdに従う
