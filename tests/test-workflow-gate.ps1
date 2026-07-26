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
    $minor = Invoke-Hook $workflowHook (New-Payload $minorSession 'UserPromptSubmit' 'README.mdの誤字を1简所だけ修正してください。軽微な単一ファイル修正です。')
    $minorTool = New-Payload $minorSession 'PreToolUse'
    $minorTool.tool_name = 'Edit'
    $minorTool.tool_input = @{ file_path = 'README.md' }
    $minorEdit = Invoke-Hook $workflowHook $minorTool
    Assert-True ($minor.Text -eq '' -and $minorEdit.Text -eq '') '軽微な単一ファイル修正は停止しない'

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
    Assert-True ((Get-Decision $designOnlyWrite) -eq 'deny') '変更動詞のない設計依頼も未選択なら停止する'

    $delegateOnlySession = 'delegate-only-session'
    $null = Invoke-Hook $workflowHook (New-Payload $delegateOnlySession 'UserPromptSubmit' 'Claudeへレビューを委譲してください。')
    $delegateOnlyTool = New-Payload $delegateOnlySession 'PreToolUse'
    $delegateOnlyTool.tool_name = 'Agent'
    $delegateOnlyTool.tool_input = @{ subagent_type = 'code-reviewer'; model = 'sonnet' }
    $delegateOnlyAgent = Invoke-Hook $workflowHook $delegateOnlyTool
    Assert-True ((Get-Decision $delegateOnlyAgent) -eq 'deny') '変更動詞のない委譲依頼も未選択なら停止する'

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
    $recommendationStop.last_assistant_message = '担当AIはCodex、モデルはgpt-5.6-sol、思考深度はhighを推奨します。品質は高い一方、費用と所要時間が増えます。この選択でよいですか。回答を待ちます。'
    $null = Invoke-Hook $workflowHook $recommendationStop
    $answer = Invoke-Hook $workflowHook (New-Payload $answerSession 'UserPromptSubmit' '推奨案で進めてください。')
    $answerTool = New-Payload $answerSession 'PreToolUse'
    $answerTool.tool_name = 'Write'
    $answerTool.tool_input = @{ file_path = 'feature.cs' }
    $answerWrite = Invoke-Hook $workflowHook $answerTool
    Assert-True ($answer.Text -eq '' -and $answerWrite.Text -eq '') '同一会話で回答済みなら再確認しない'

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
    $goodStop.last_assistant_message = '担当AIはCodex、モデルはgpt-5.6-sol、思考深度はhighを推奨します。品質は高い一方、費用と所要時間が増えます。この選択でよいですか。回答を待ちます。'
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
