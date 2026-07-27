[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$workflowHook = Join-Path $repo 'Codex\hooks\workflow_gate.ps1'
$agentHook = Join-Path $repo 'Claude\hooks\require_agent_model.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("airules-workflow-tests-" + [guid]::NewGuid().ToString('N'))
$stateRoot = Join-Path $testRoot 'state'
$env:AIRULES_WORKFLOW_STATE_ROOT = $stateRoot
$passed = 0
$failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        $script:passed++
        Write-Host "PASS: $Name"
    } else {
        $script:failed++
        Write-Host "FAIL: $Name"
    }
}

function Invoke-Hook {
    param([string]$Script, [hashtable]$Payload)
    $json = $Payload | ConvertTo-Json -Compress -Depth 10
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh).Source
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($Script)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $process.StandardInput.Write($json)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()
    $output = if ($stdout) { $stdout.TrimEnd() } elseif ($stderr) { $stderr.TrimEnd() } else { '' }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = $output
        Json = if ($stdout) {
            try { $stdout | ConvertFrom-Json } catch { $null }
        } else { $null }
    }
}

function New-Payload {
    param([string]$Session, [string]$Event, [string]$Prompt = '')
    return @{
        session_id = $Session
        cwd = $testRoot
        hook_event_name = $Event
        prompt = $Prompt
    }
}

function Get-Decision {
    param([object]$Result)
    if ($null -eq $Result.Json) { return '' }
    if ($Result.Json.decision) { return [string]$Result.Json.decision }
    return [string]$Result.Json.hookSpecificOutput.permissionDecision
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    $minorSession = 'minor-session'
    $minor = Invoke-Hook $workflowHook (New-Payload $minorSession 'UserPromptSubmit' 'README.mdの誤字を1箇所だけ修正してください。')
    $minorTool = New-Payload $minorSession 'PreToolUse'
    $minorTool.tool_name = 'Edit'
    $minorTool.tool_input = @{ file_path = 'README.md' }
    $minorEdit = Invoke-Hook $workflowHook $minorTool
    Assert-True ($minor.Text -eq '' -and $minorEdit.Text -eq '') '対象と単一箇所が明確な局所修正は停止しない'

    $minorWithTestSession = 'minor-with-test-session'
    $minorWithTest = Invoke-Hook $workflowHook (New-Payload $minorWithTestSession 'UserPromptSubmit' 'Foo.csの既存メソッド内の比較演算子1箇所だけ修正し、FooTests.csの対応テストだけ更新してください。')
    $minorWithTestTool = New-Payload $minorWithTestSession 'PreToolUse'
    $minorWithTestTool.tool_name = 'Edit'
    $minorWithTestTool.tool_input = @{ file_path = 'Foo.cs' }
    $minorWithTestEdit = Invoke-Hook $workflowHook $minorWithTestTool
    Assert-True ($minorWithTest.Text -eq '' -and $minorWithTestEdit.Text -eq '') '実装1ファイルと直接対応する既存テスト1つの局所修正は停止しない'

    $claimedMinorSession = 'claimed-minor-session'
    $null = Invoke-Hook $workflowHook (New-Payload $claimedMinorSession 'UserPromptSubmit' 'Bug.csの軽微な修正です。簡単なのでそのまま修正してください。')
    $claimedMinorTool = New-Payload $claimedMinorSession 'PreToolUse'
    $claimedMinorTool.tool_name = 'Edit'
    $claimedMinorTool.tool_input = @{ file_path = 'Bug.cs' }
    $claimedMinorEdit = Invoke-Hook $workflowHook $claimedMinorTool
    Assert-True ((Get-Decision $claimedMinorEdit) -eq 'deny') '軽微という自己申告だけでは停止を解除しない'

    $minorPublicApiSession = 'minor-public-api-session'
    $null = Invoke-Hook $workflowHook (New-Payload $minorPublicApiSession 'UserPromptSubmit' 'Api.csのPublic APIにある比較演算子1箇所だけ修正してください。')
    $minorPublicApiTool = New-Payload $minorPublicApiSession 'PreToolUse'
    $minorPublicApiTool.tool_name = 'Edit'
    $minorPublicApiTool.tool_input = @{ file_path = 'Api.cs' }
    $minorPublicApiEdit = Invoke-Hook $workflowHook $minorPublicApiTool
    Assert-True ((Get-Decision $minorPublicApiEdit) -eq 'deny') 'Public APIに触れる局所修正は軽微扱いしない'

    $minorConfigSession = 'minor-config-session'
    $null = Invoke-Hook $workflowHook (New-Payload $minorConfigSession 'UserPromptSubmit' 'Settings.csの設定定数1箇所だけ変更してください。')
    $minorConfigTool = New-Payload $minorConfigSession 'PreToolUse'
    $minorConfigTool.tool_name = 'Edit'
    $minorConfigTool.tool_input = @{ file_path = 'Settings.cs' }
    $minorConfigEdit = Invoke-Hook $workflowHook $minorConfigTool
    Assert-True ((Get-Decision $minorConfigEdit) -eq 'deny') '設定に触れる局所修正は軽微扱いしない'

    $minorNewFileSession = 'minor-new-file-session'
    $null = Invoke-Hook $workflowHook (New-Payload $minorNewFileSession 'UserPromptSubmit' 'Helper.csを新規ファイルとして作り、条件式1箇所だけ追加してください。')
    $minorNewFileTool = New-Payload $minorNewFileSession 'PreToolUse'
    $minorNewFileTool.tool_name = 'Write'
    $minorNewFileTool.tool_input = @{ file_path = 'Helper.cs' }
    $minorNewFileWrite = Invoke-Hook $workflowHook $minorNewFileTool
    Assert-True ((Get-Decision $minorNewFileWrite) -eq 'deny') '新規ファイルを伴う局所実装は軽微扱いしない'

    $minorTwoFilesSession = 'minor-two-files-session'
    $null = Invoke-Hook $workflowHook (New-Payload $minorTwoFilesSession 'UserPromptSubmit' 'Foo.csとBar.csの条件式をそれぞれ1箇所だけ修正してください。')
    $minorTwoFilesTool = New-Payload $minorTwoFilesSession 'PreToolUse'
    $minorTwoFilesTool.tool_name = 'Edit'
    $minorTwoFilesTool.tool_input = @{ file_path = 'Foo.cs' }
    $minorTwoFilesEdit = Invoke-Hook $workflowHook $minorTwoFilesTool
    Assert-True ((Get-Decision $minorTwoFilesEdit) -eq 'deny') '実装ファイル2つの局所修正は軽微扱いしない'

    $researchSession = 'research-session'
    $research = Invoke-Hook $workflowHook (New-Payload $researchSession 'UserPromptSubmit' 'Public API変更の影響を調査して説明してください。実装や設定変更はしません。')
    $researchTool = New-Payload $researchSession 'PreToolUse'
    $researchTool.tool_name = 'Write'
    $researchTool.tool_input = @{ file_path = 'should-not-be-used.md' }
    $researchWrite = Invoke-Hook $workflowHook $researchTool
    Assert-True ($research.Text -eq '' -and $researchWrite.Text -eq '') '変更対象に言及する調査・説明だけの依頼は選択待ちにしない'

    $questionSession = 'question-session'
    $question = Invoke-Hook $workflowHook (New-Payload $questionSession 'UserPromptSubmit' 'このPublic APIは変更できる？ まず可否だけ回答して。')
    $questionTool = New-Payload $questionSession 'PreToolUse'
    $questionTool.tool_name = 'Write'
    $questionTool.tool_input = @{ file_path = 'should-not-be-used.md' }
    $questionWrite = Invoke-Hook $workflowHook $questionTool
    Assert-True ($question.Text -eq '' -and $questionWrite.Text -eq '') '実装可否の質問回答だけなら選択待ちにしない'

    $designQuestionSession = 'design-question-session'
    $designQuestion = Invoke-Hook $workflowHook (New-Payload $designQuestionSession 'UserPromptSubmit' 'この機能に新しい状態遷移の設計は必要？ 理由だけ教えて。')
    $designQuestionTool = New-Payload $designQuestionSession 'PreToolUse'
    $designQuestionTool.tool_name = 'Write'
    $designQuestionTool.tool_input = @{ file_path = 'should-not-be-used.md' }
    $designQuestionWrite = Invoke-Hook $workflowHook $designQuestionTool
    Assert-True ($designQuestion.Text -eq '' -and $designQuestionWrite.Text -eq '') '設計に言及する疑問への回答だけなら選択待ちにしない'

    $embeddedRulesSession = 'embedded-rules-session'
    $embeddedRulesPrompt = @'
# AGENTS.md instructions
<INSTRUCTIONS>
Public API、データ構造、設計、実装、レビューではモデルを選択する。
</INSTRUCTIONS>
<environment_context>
  <cwd>D:\AIRules\AIRules</cwd>
</environment_context>
deploy.ps1を実行するとCodex Hookもグローバルへ配備される？ 質問への回答だけお願いします。
'@
    $embeddedRules = Invoke-Hook $workflowHook (New-Payload $embeddedRulesSession 'UserPromptSubmit' $embeddedRulesPrompt)
    $embeddedRulesTool = New-Payload $embeddedRulesSession 'PreToolUse'
    $embeddedRulesTool.tool_name = 'Write'
    $embeddedRulesTool.tool_input = @{ file_path = 'should-not-be-used.md' }
    $embeddedRulesWrite = Invoke-Hook $workflowHook $embeddedRulesTool
    Assert-True ($embeddedRules.Text -eq '' -and $embeddedRulesWrite.Text -eq '') '添付されたAGENTS指示本文を現在の作業依頼として分類しない'

    $designSession = 'design-session'
    $design = Invoke-Hook $workflowHook (New-Payload $designSession 'UserPromptSubmit' '状態データ、公開API、UIをまたぐ機能を設計して実装してください。責務分割と依存方向も決めてください。')
    $designTool = New-Payload $designSession 'PreToolUse'
    $designTool.tool_name = 'Write'
    $designTool.tool_input = @{ file_path = 'src/new.cs' }
    $designWrite = Invoke-Hook $workflowHook $designTool
    Assert-True ((Get-Decision $designWrite) -eq 'deny') '設計を伴う複数責務の実装は未選択なら停止する'

    $singleDesignSession = 'single-design-session'
    $null = Invoke-Hook $workflowHook (New-Payload $singleDesignSession 'UserPromptSubmit' '既存責務と依存方向を決める設計を行い、サービスを実装してください。')
    $singleDesignTool = New-Payload $singleDesignSession 'PreToolUse'
    $singleDesignTool.tool_name = 'Write'
    $singleDesignTool.tool_input = @{ file_path = 'service.cs' }
    $singleDesignWrite = Invoke-Hook $workflowHook $singleDesignTool
    Assert-True ((Get-Decision $singleDesignWrite) -eq 'deny') '設計判断を含む変更は単一責務でも未選択なら停止する'

    $designOnlySession = 'design-only-session'
    $null = Invoke-Hook $workflowHook (New-Payload $designOnlySession 'UserPromptSubmit' 'Public APIを設計してください。')
    $designOnlyTool = New-Payload $designOnlySession 'PreToolUse'
    $designOnlyTool.tool_name = 'Write'
    $designOnlyTool.tool_input = @{ file_path = 'api-design.md' }
    $designOnlyWrite = Invoke-Hook $workflowHook $designOnlyTool
    Assert-True ($designOnlyWrite.Text -eq '') 'コード変更を伴わない設計だけの依頼は停止しない'

    $reviewOnlySession = 'review-only-session'
    $null = Invoke-Hook $workflowHook (New-Payload $reviewOnlySession 'UserPromptSubmit' '現在の差分をレビューしてください。変更はしないでください。')
    $reviewOnlyTool = New-Payload $reviewOnlySession 'PreToolUse'
    $reviewOnlyTool.tool_name = 'Write'
    $reviewOnlyTool.tool_input = @{ file_path = 'review.md' }
    $reviewOnlyWrite = Invoke-Hook $workflowHook $reviewOnlyTool
    Assert-True ($reviewOnlyWrite.Text -eq '') 'コード変更を伴わないレビューだけの依頼は停止しない'

    $diffCheckSession = 'diff-check-session'
    $null = Invoke-Hook $workflowHook (New-Payload $diffCheckSession 'UserPromptSubmit' '現在のコード差分を確認してください。問題点を報告してください。')
    $diffCheckTool = New-Payload $diffCheckSession 'PreToolUse'
    $diffCheckTool.tool_name = 'Agent'
    $diffCheckTool.tool_input = @{ subagent_type = 'code-reviewer'; model = 'gpt-5.6-sol' }
    $diffCheckAgent = Invoke-Hook $workflowHook $diffCheckTool
    Assert-True ($diffCheckAgent.Text -eq '') 'コード変更を伴わない差分確認は停止しない'

    $delegateOnlySession = 'delegate-only-session'
    $null = Invoke-Hook $workflowHook (New-Payload $delegateOnlySession 'UserPromptSubmit' 'Claudeへレビューを委譲してください。')
    $delegateOnlyTool = New-Payload $delegateOnlySession 'PreToolUse'
    $delegateOnlyTool.tool_name = 'Agent'
    $delegateOnlyTool.tool_input = @{ subagent_type = 'code-reviewer'; model = 'sonnet' }
    $delegateOnlyAgent = Invoke-Hook $workflowHook $delegateOnlyTool
    Assert-True ($delegateOnlyAgent.Text -eq '') '実装を伴わないレビュー委譲は停止しない'

    $reviewFixSession = 'review-fix-session'
    $null = Invoke-Hook $workflowHook (New-Payload $reviewFixSession 'UserPromptSubmit' '現在の差分をレビューし、問題があれば修正してください。')
    $reviewFixTool = New-Payload $reviewFixSession 'PreToolUse'
    $reviewFixTool.tool_name = 'Edit'
    $reviewFixTool.tool_input = @{ file_path = 'Api.cs' }
    $reviewFixEdit = Invoke-Hook $workflowHook $reviewFixTool
    Assert-True ((Get-Decision $reviewFixEdit) -eq 'deny') 'レビュー後のコード修正まで含む依頼は未選択なら停止する'

    $noCodingSession = 'no-coding-session'
    $noCoding = Invoke-Hook $workflowHook (New-Payload $noCodingSession 'UserPromptSubmit' 'コーディングを伴わない相談です。設計とレビューの進め方を説明してください。')
    $noCodingTool = New-Payload $noCodingSession 'PreToolUse'
    $noCodingTool.tool_name = 'Write'
    $noCodingTool.tool_input = @{ file_path = 'should-not-be-used.md' }
    $noCodingWrite = Invoke-Hook $workflowHook $noCodingTool
    Assert-True ($noCoding.Text -eq '' -and $noCodingWrite.Text -eq '') 'コーディングを伴わない相談・設計・レビューは停止しない'

    $implementationConsultSession = 'implementation-consult-session'
    $implementationConsult = Invoke-Hook $workflowHook (New-Payload $implementationConsultSession 'UserPromptSubmit' 'この機能の実装について相談したい。選択肢を説明して。')
    $implementationConsultTool = New-Payload $implementationConsultSession 'PreToolUse'
    $implementationConsultTool.tool_name = 'Write'
    $implementationConsultTool.tool_input = @{ file_path = 'should-not-be-used.md' }
    $implementationConsultWrite = Invoke-Hook $workflowHook $implementationConsultTool
    Assert-True ($implementationConsult.Text -eq '' -and $implementationConsultWrite.Text -eq '') '実装という語を含む相談だけでは停止しない'

    $terseImplementationSession = 'terse-implementation-session'
    $null = Invoke-Hook $workflowHook (New-Payload $terseImplementationSession 'UserPromptSubmit' 'Public API変更')
    $terseImplementationTool = New-Payload $terseImplementationSession 'PreToolUse'
    $terseImplementationTool.tool_name = 'Edit'
    $terseImplementationTool.tool_input = @{ file_path = 'Api.cs' }
    $terseImplementationEdit = Invoke-Hook $workflowHook $terseImplementationTool
    Assert-True ((Get-Decision $terseImplementationEdit) -eq 'deny') '短い実変更指示は未選択なら停止する'

    $multiSession = 'multi-responsibility-session'
    $null = Invoke-Hook $workflowHook (New-Payload $multiSession 'UserPromptSubmit' 'API、保存データ、UIをまとめて変更してください。')
    $multiTool = New-Payload $multiSession 'PreToolUse'
    $multiTool.tool_name = 'Edit'
    $multiTool.tool_input = @{ file_path = 'feature.cs' }
    $multiEdit = Invoke-Hook $workflowHook $multiTool
    Assert-True ((Get-Decision $multiEdit) -eq 'deny') '複数責務変更は設計という語がなくても未選択なら停止する'

    $publicSession = 'public-api-session'
    $null = Invoke-Hook $workflowHook (New-Payload $publicSession 'UserPromptSubmit' 'Public APIを変更して呼び出し側も修正してください。')
    $publicTool = New-Payload $publicSession 'PreToolUse'
    $publicTool.tool_name = 'Edit'
    $publicTool.tool_input = @{ file_path = 'api.cs' }
    $publicEdit = Invoke-Hook $workflowHook $publicTool
    Assert-True ((Get-Decision $publicEdit) -eq 'deny') 'Public API変更は未選択なら停止する'

    $selectedSession = 'selected-session'
    $selected = Invoke-Hook $workflowHook (New-Payload $selectedSession 'UserPromptSubmit' '担当AI=Codex、model=gpt-5.6-sol、reasoning_effort=highでPublic APIを変更してください。')
    $selectedTool = New-Payload $selectedSession 'PreToolUse'
    $selectedTool.tool_name = 'Edit'
    $selectedTool.tool_input = @{ file_path = 'api.cs' }
    $selectedEdit = Invoke-Hook $workflowHook $selectedTool
    Assert-True ($selected.Text -eq '' -and $selectedEdit.Text -eq '') '担当・モデル・思考深度が指定済みなら停止しない'

    $answerSession = 'answer-session'
    $null = Invoke-Hook $workflowHook (New-Payload $answerSession 'UserPromptSubmit' 'API、データ、UIをまたぐ設計実装をしてください。')
    $prematureAnswer = Invoke-Hook $workflowHook (New-Payload $answerSession 'UserPromptSubmit' 'OK')
    $prematureTool = New-Payload $answerSession 'PreToolUse'
    $prematureTool.tool_name = 'Write'
    $prematureTool.tool_input = @{ file_path = 'feature.cs' }
    $prematureWrite = Invoke-Hook $workflowHook $prematureTool
    Assert-True ((Get-Decision $prematureWrite) -eq 'deny') '推奨案提示前の短い承認語では選択済みにしない'

    $recommendationStop = New-Payload $answerSession 'Stop'
    $recommendationStop.last_assistant_message = '現在のモデルはgpt-5.6-sol、思考深度はmediumです。担当AIはCodex、モデルはgpt-5.6-sol、思考深度はhigh、Sub Agentなしを推奨します。品質は高い一方、費用と所要時間が増えます。この選択でよいですか。回答を待ちます。'
    $null = Invoke-Hook $workflowHook $recommendationStop
    $answer = Invoke-Hook $workflowHook (New-Payload $answerSession 'UserPromptSubmit' '推奨案で進めてください。')
    $answerTool = New-Payload $answerSession 'PreToolUse'
    $answerTool.tool_name = 'Write'
    $answerTool.tool_input = @{ file_path = 'feature.cs' }
    $answerWrite = Invoke-Hook $workflowHook $answerTool
    Assert-True ($answer.Text -eq '' -and $answerWrite.Text -eq '') '同一会話で回答済みなら再確認しない'

    $naturalAnswerSession = 'natural-answer-session'
    $null = Invoke-Hook $workflowHook (New-Payload $naturalAnswerSession 'UserPromptSubmit' 'Api.csを修正してください。')
    $naturalRecommendation = New-Payload $naturalAnswerSession 'Stop'
    $naturalRecommendation.last_assistant_message = '現在のモデルはgpt-5.6-sol、思考深度はmediumです。担当AIはCodex、モデルはgpt-5.6-sol、思考深度はmedium、Sub Agentなしを推奨します。品質は十分で、費用と時間を抑えられます。よいですか。'
    $null = Invoke-Hook $workflowHook $naturalRecommendation
    $naturalAnswer = Invoke-Hook $workflowHook (New-Payload $naturalAnswerSession 'UserPromptSubmit' 'よい')
    $naturalAnswerTool = New-Payload $naturalAnswerSession 'PreToolUse'
    $naturalAnswerTool.tool_name = 'Edit'
    $naturalAnswerTool.tool_input = @{ file_path = 'Api.cs' }
    $naturalAnswerEdit = Invoke-Hook $workflowHook $naturalAnswerTool
    Assert-True ($naturalAnswer.Text -eq '' -and $naturalAnswerEdit.Text -eq '') '推奨提示後の自然な短文承認を選択済みとして扱う'

    $currentModelSession = 'current-model-session'
    $currentModel = Invoke-Hook $workflowHook (New-Payload $currentModelSession 'UserPromptSubmit' '今のモデルでそのまま修正を進めて。')
    $currentModelTool = New-Payload $currentModelSession 'PreToolUse'
    $currentModelTool.tool_name = 'Edit'
    $currentModelTool.tool_input = @{ file_path = 'Api.cs' }
    $currentModelEdit = Invoke-Hook $workflowHook $currentModelTool
    Assert-True ($currentModel.Text -eq '' -and $currentModelEdit.Text -eq '') '現在モデルでの続行指示を定型文なしで選択済みとして扱う'

    $flowReview = Invoke-Hook $workflowHook (New-Payload $answerSession 'UserPromptSubmit' '実装が終わったので、そのまま差分をレビューしてください。')
    $flowReviewTool = New-Payload $answerSession 'PreToolUse'
    $flowReviewTool.tool_name = 'Agent'
    $flowReviewTool.tool_input = @{ subagent_type = 'code-reviewer'; model = 'gpt-5.6-sol' }
    $flowReviewAgent = Invoke-Hook $workflowHook $flowReviewTool
    Assert-True ($flowReview.Text -eq '' -and $flowReviewAgent.Text -eq '') '同じ作業の設計・実装・レビューでは選択を一度だけ再利用する'

    $pausedSession = 'paused-pending-session'
    $null = Invoke-Hook $workflowHook (New-Payload $pausedSession 'UserPromptSubmit' 'Api.csを修正してください。')
    $pendingReadTool = New-Payload $pausedSession 'PreToolUse'
    $pendingReadTool.tool_name = 'mcp__node_repl__js'
    $pendingReadTool.tool_input = 'const scene = await tools.mcp__unityMCP__get_scene_info({}); text(scene);'
    $pendingRead = Invoke-Hook $workflowHook $pendingReadTool
    Assert-True ($pendingRead.Text -eq '') '選択待ちでも変更を含まないNode REPL読取コードは通す'

    $pausedPrompt = Invoke-Hook $workflowHook (New-Payload $pausedSession 'UserPromptSubmit' 'ところで、この機能の用途を説明して。')
    $pausedTool = New-Payload $pausedSession 'PreToolUse'
    $pausedTool.tool_name = 'Write'
    $pausedTool.tool_input = @{ file_path = 'should-not-be-used.md' }
    $pausedWrite = Invoke-Hook $workflowHook $pausedTool
    $pausedStop = New-Payload $pausedSession 'Stop'
    $pausedStop.last_assistant_message = '用途を説明します。'
    $pausedStopResult = Invoke-Hook $workflowHook $pausedStop
    Assert-True ($pausedPrompt.Text -eq '' -and $pausedWrite.Text -eq '' -and (Get-Decision $pausedStopResult) -eq '') '選択待ちを途中の質問・説明へ持ち越して強制しない'

    $resumedPrompt = Invoke-Hook $workflowHook (New-Payload $pausedSession 'UserPromptSubmit' 'ではApi.csを修正してください。')
    $resumedTool = New-Payload $pausedSession 'PreToolUse'
    $resumedTool.tool_name = 'Edit'
    $resumedTool.tool_input = @{ file_path = 'Api.cs' }
    $resumedEdit = Invoke-Hook $workflowHook $resumedTool
    Assert-True ((Get-Decision $resumedEdit) -eq 'deny') '実作業へ戻った時だけ選択待ちを再開する'

    $pendingMutationTool = New-Payload $pausedSession 'PreToolUse'
    $pendingMutationTool.tool_name = 'mcp__node_repl__js'
    $pendingMutationTool.tool_input = @{ code = 'await fs.promises.writeFile("Api.cs", "changed");' }
    $pendingMutation = Invoke-Hook $workflowHook $pendingMutationTool
    Assert-True ((Get-Decision $pendingMutation) -eq 'deny') 'Node REPLの変更コードは選択待ちなら停止する'

    $legacySession = 'legacy-state-session'
    $legacyBytes = [Text.Encoding]::UTF8.GetBytes($legacySession)
    $legacyHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($legacyBytes)).Replace('-', '').ToLowerInvariant()
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $stateRoot "$legacyHash.json"), (@{
        schemaVersion = 1
        sessionId = $legacySession
        cwd = $testRoot
        status = 'pending'
        reasons = @('実装・修正')
    } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $legacyTool = New-Payload $legacySession 'PreToolUse'
    $legacyTool.tool_name = 'Write'
    $legacyTool.tool_input = @{ file_path = 'legacy.md' }
    $legacyWrite = Invoke-Hook $workflowHook $legacyTool
    Assert-True ($legacyWrite.Text -eq '') '旧schemaのpending状態を無効化する'

    $currentSession = 'current-ai-session'
    $current = Invoke-Hook $workflowHook (New-Payload $currentSession 'UserPromptSubmit' '現在起動中のAIでそのままPublic API変更を進めて構いません。ここでは確認待ちにしないでください。')
    $currentTool = New-Payload $currentSession 'PreToolUse'
    $currentTool.tool_name = 'Edit'
    $currentTool.tool_input = @{ file_path = 'api.cs' }
    $currentEdit = Invoke-Hook $workflowHook $currentTool
    Assert-True ($current.Text -eq '' -and $currentEdit.Text -eq '') '現在のAIで確認不要という明示を選択済みとして扱う'

    $newWorkSession = 'new-work-session'
    $null = Invoke-Hook $workflowHook (New-Payload $newWorkSession 'UserPromptSubmit' '担当AI=Codex、model=gpt-5.6-sol、reasoning_effort=highでPublic APIを変更してください。')
    $null = Invoke-Hook $workflowHook (New-Payload $newWorkSession 'UserPromptSubmit' '別件です。APIとUIをまたぐ設計実装をしてください。')
    $newWorkTool = New-Payload $newWorkSession 'PreToolUse'
    $newWorkTool.tool_name = 'Write'
    $newWorkTool.tool_input = @{ file_path = 'other.cs' }
    $newWorkWrite = Invoke-Hook $workflowHook $newWorkTool
    Assert-True ((Get-Decision $newWorkWrite) -eq 'deny') '同じ会話でも明示された別作業では選択をリセットする'

    $planPath = Join-Path $testRoot 'PLAN.md'
    [IO.File]::WriteAllText($planPath, 'AIRULES_WORKFLOW_SELECTION: owner=Codex; model=gpt-5.6-sol; thinking=medium; scope=認証API移行', [Text.UTF8Encoding]::new($false))
    $planSession = 'plan-session'
    $plan = Invoke-Hook $workflowHook (New-Payload $planSession 'UserPromptSubmit' 'PLAN.mdの作業を再開し、Public APIを変更してください。')
    $planTool = New-Payload $planSession 'PreToolUse'
    $planTool.tool_name = 'Edit'
    $planTool.tool_input = @{ file_path = 'auth.cs' }
    $planEdit = Invoke-Hook $workflowHook $planTool
    Assert-True ($plan.Text -eq '' -and $planEdit.Text -eq '') 'PLAN.mdの有効な選択を再利用する'

    $readAgent = New-Payload $publicSession 'PreToolUse'
    $readAgent.tool_name = 'Agent'
    $readAgent.tool_input = @{ subagent_type = 'Explore' }
    $explore = Invoke-Hook $workflowHook $readAgent
    Assert-True ($explore.Text -eq '') 'Explore読取専用Agentはworkflow gateで妨げない'

    $missingModel = Invoke-Hook $agentHook @{ tool_name = 'Agent'; tool_input = @{ subagent_type = 'general-purpose' } }
    $withModel = Invoke-Hook $agentHook @{ tool_name = 'Agent'; tool_input = @{ subagent_type = 'general-purpose'; model = 'sonnet' } }
    $exploreModel = Invoke-Hook $agentHook @{ tool_name = 'Agent'; tool_input = @{ subagent_type = 'Explore' } }
    Assert-True ((Get-Decision $missingModel) -eq 'deny') 'model未指定Sub Agentは従来どおり拒否する'
    Assert-True ((Get-Decision $withModel) -eq 'allow') 'model指定済みSub Agentは許可する'
    Assert-True ((Get-Decision $exploreModel) -eq 'allow') 'require_agent_modelもExploreを許可する'

    $stopSession = 'stop-session'
    $null = Invoke-Hook $workflowHook (New-Payload $stopSession 'UserPromptSubmit' 'APIとUIをまたぐ設計実装をしてください。')
    $badStop = New-Payload $stopSession 'Stop'
    $badStop.last_assistant_message = '実装を開始します。'
    $badStopResult = Invoke-Hook $workflowHook $badStop
    $goodStop = New-Payload $stopSession 'Stop'
    $goodStop.last_assistant_message = '現在のモデルはgpt-5.6-sol、思考深度はmediumです。担当AIはCodex、モデルはgpt-5.6-sol、思考深度はhigh、Sub Agentなしを推奨します。品質は高い一方、費用と所要時間が増えます。この選択でよいですか。回答を待ちます。'
    $goodStopResult = Invoke-Hook $workflowHook $goodStop
    Assert-True ((Get-Decision $badStopResult) -eq 'block' -and (Get-Decision $goodStopResult) -eq '') 'Stopは推奨提示漏れを差し戻し、適切な確認応答を通す'

    $testHome = Join-Path $testRoot 'home'
    $backup = Join-Path $testRoot 'backup'
    New-Item -ItemType Directory -Path (Join-Path $testHome '.claude'),(Join-Path $testHome '.codex') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $testHome '.claude\settings.json'), @'
{
  "theme": "dark",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "user-owned-hook --check" }
        ]
      }
    ]
  }
}
'@, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $testHome '.codex\hooks.json'), @'
{
  "description": "user hooks",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "user-session-hook" }
        ]
      }
    ]
  }
}
'@, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $testHome '.codex\config.toml'), "[features]`r`nhooks = false`r`n", [Text.UTF8Encoding]::new($false))

    & (Join-Path $repo 'deploy.ps1') -HomeDirectory $testHome -BackupDirectory $backup | Out-Null
    $firstExit = $LASTEXITCODE
    $claudeSettings = Get-Content (Join-Path $testHome '.claude\settings.json') -Raw | ConvertFrom-Json
    $codexHooks = Get-Content (Join-Path $testHome '.codex\hooks.json') -Raw | ConvertFrom-Json
    $configText = Get-Content (Join-Path $testHome '.codex\config.toml') -Raw
    $preserved = $claudeSettings.theme -eq 'dark' -and
        (@($claudeSettings.hooks.PreToolUse.hooks.command) -contains 'user-owned-hook --check' -or
         @($claudeSettings.hooks.PreToolUse | ForEach-Object { $_.hooks.command }) -contains 'user-owned-hook --check') -and
        @($codexHooks.hooks.SessionStart | ForEach-Object { $_.hooks.command }) -contains 'user-session-hook' -and
        $configText -match '(?m)^hooks\s*=\s*true\s*$'
    Assert-True ($firstExit -eq 0 -and $preserved) 'AIRules管理外の既存設定・Hookを保持しCodex hooksを有効化する'

    $tracked = @(
        (Join-Path $testHome '.claude\settings.json'),
        (Join-Path $testHome '.codex\hooks.json'),
        (Join-Path $testHome '.codex\config.toml'),
        (Join-Path $testHome '.claude\skills\airules-workflow\SKILL.md'),
        (Join-Path $testHome '.claude\AGENTS.md'),
        (Join-Path $testHome '.codex\AGENTS.md')
    )
    $before = @{}
    foreach ($path in $tracked) { $before[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    & (Join-Path $repo 'deploy.ps1') -HomeDirectory $testHome -BackupDirectory $backup | Out-Null
    $secondExit = $LASTEXITCODE
    $same = $true
    foreach ($path in $tracked) {
        if ($before[$path] -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) { $same = $false }
    }
    Assert-True ($secondExit -eq 0 -and $same) '配備を2回実行しても管理対象の結果が変わらない'

    $lockedHookPath = Join-Path $testHome '.claude\hooks\workflow_gate.ps1'
    $beforeLocked = @{}
    foreach ($path in $tracked) { $beforeLocked[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    $lockStream = [IO.File]::Open($lockedHookPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        & (Join-Path $repo 'deploy.ps1') -HomeDirectory $testHome -BackupDirectory $backup *> $null
        $lockedExit = $LASTEXITCODE
    } finally {
        $lockStream.Dispose()
    }
    $lockedUnchanged = $true
    foreach ($path in $tracked) {
        if ($beforeLocked[$path] -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) { $lockedUnchanged = $false }
    }
    Assert-True ($lockedExit -ne 0 -and $lockedUnchanged) 'Hook本体を配置不能なら設定切替前に停止し部分配備しない'

    $collisionHome = Join-Path $testRoot 'collision-home'
    New-Item -ItemType Directory -Path (Join-Path $collisionHome '.claude\hooks'),(Join-Path $collisionHome '.codex') -Force | Out-Null
    $collisionSettingsPath = Join-Path $collisionHome '.claude\settings.json'
    $collisionHookPath = Join-Path $collisionHome '.claude\hooks\workflow_gate.ps1'
    $collisionSettingsText = '{ "sentinel": "keep" }'
    $collisionHookText = '# user-owned workflow hook'
    [IO.File]::WriteAllText($collisionSettingsPath, $collisionSettingsText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($collisionHookPath, $collisionHookText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $collisionHome '.codex\config.toml'), "[features]`r`nhooks = false`r`n", [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'deploy.ps1') -HomeDirectory $collisionHome -BackupDirectory (Join-Path $testRoot 'collision-backup') *> $null
    $collisionExit = $LASTEXITCODE
    $collisionUnchanged = (Get-Content $collisionSettingsPath -Raw) -eq $collisionSettingsText -and (Get-Content $collisionHookPath -Raw) -eq $collisionHookText
    Assert-True ($collisionExit -ne 0 -and $collisionUnchanged) '同名のAIRules管理外Hookは上書きせず配備を停止する'

    $brokenHome = Join-Path $testRoot 'broken-home'
    New-Item -ItemType Directory -Path (Join-Path $brokenHome '.claude') -Force | Out-Null
    $brokenPath = Join-Path $brokenHome '.claude\settings.json'
    $brokenText = '{ broken json'
    [IO.File]::WriteAllText($brokenPath, $brokenText, [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'deploy.ps1') -HomeDirectory $brokenHome -BackupDirectory (Join-Path $testRoot 'broken-backup') *> $null
    $brokenExit = $LASTEXITCODE
    $unchanged = (Get-Content $brokenPath -Raw) -eq $brokenText
    Assert-True ($brokenExit -ne 0 -and $unchanged) '壊れたJSONでは停止しユーザー設定を変更しない'

    $brokenCodexHome = Join-Path $testRoot 'broken-codex-home'
    New-Item -ItemType Directory -Path (Join-Path $brokenCodexHome '.claude'),(Join-Path $brokenCodexHome '.codex') -Force | Out-Null
    $validClaudePath = Join-Path $brokenCodexHome '.claude\settings.json'
    $brokenCodexPath = Join-Path $brokenCodexHome '.codex\hooks.json'
    $validClaudeText = '{ "sentinel": "keep" }'
    $brokenCodexText = '{ broken hooks'
    [IO.File]::WriteAllText($validClaudePath, $validClaudeText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($brokenCodexPath, $brokenCodexText, [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'deploy.ps1') -HomeDirectory $brokenCodexHome -BackupDirectory (Join-Path $testRoot 'broken-codex-backup') *> $null
    $brokenCodexExit = $LASTEXITCODE
    $bothUnchanged = (Get-Content $validClaudePath -Raw) -eq $validClaudeText -and (Get-Content $brokenCodexPath -Raw) -eq $brokenCodexText
    Assert-True ($brokenCodexExit -ne 0 -and $bothUnchanged) '壊れたCodex hooks.jsonでも全ユーザー設定を書き換えない'

    $malformed = Invoke-Hook $workflowHook @{}
    Assert-True ($malformed.ExitCode -eq 0 -and $malformed.Text -eq '') '想定外payloadはfail openで通常作業を破壊しない'
} finally {
    Remove-Item Env:AIRULES_WORKFLOW_STATE_ROOT -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testRoot).Path)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolved).StartsWith('airules-workflow-tests-')) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

Write-Host "RESULT: passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
