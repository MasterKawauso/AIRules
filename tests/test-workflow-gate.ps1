[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$workflowHook = Join-Path $repo 'Codex\hooks\workflow_gate.ps1'
$agentHook = Join-Path $repo 'Claude\hooks\require_agent_model.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("airules-workflow-tests-" + [guid]::NewGuid().ToString('N'))
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

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    foreach ($hookPath in @($workflowHook, $agentHook)) {
        foreach ($eventName in @('UserPromptSubmit', 'PreToolUse', 'Stop')) {
            $result = Invoke-Hook $hookPath @{
                session_id = 'old-pending-session'
                cwd = $testRoot
                hook_event_name = $eventName
                prompt = 'APIとデータ構造を変更して実装して'
                tool_name = 'Agent'
                tool_input = @{ subagent_type = 'general-purpose'; prompt = '実装して' }
            }
            Assert-True ($result.ExitCode -eq 0 -and $result.Text -eq '') "$([IO.Path]::GetFileName($hookPath)) / $eventName はモデル選択・権限判断へ介入しない"
        }
    }

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

    # Seed the previous release's registrations, sharing entries with user hooks.
    # A similarly named command outside the managed path must also survive.
    foreach ($client in @('claude', 'codex')) {
        $clientHome = Join-Path $testHome ".$client"
        New-Item -ItemType Directory -Path (Join-Path $clientHome 'hooks') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $clientHome 'hooks\workflow_gate.ps1'),
            "# AIRULES-MANAGED-HOOK schema=1 source=Codex/hooks/workflow_gate.ps1`nthrow 'old gate'`n", [Text.UTF8Encoding]::new($false))
        $configPath = Join-Path $clientHome $(if ($client -eq 'claude') { 'settings.json' } else { 'hooks.json' })
        $document = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
        foreach ($eventName in @('PreToolUse', 'UserPromptSubmit', 'Stop')) {
            $commands = @(
                @{ type = 'command'; command = "pwsh -NoProfile -File `"$clientHome\hooks\workflow_gate.ps1`"" },
                @{ type = 'command'; command = "user-$eventName-hook" },
                @{ type = 'command'; command = 'pwsh -NoProfile -File "D:\user-hooks\workflow_gate.ps1"' }
            )
            if ($client -eq 'claude' -and $eventName -eq 'PreToolUse') {
                $commands += @{ type = 'command'; command = "pwsh -NoProfile -File `"$clientHome\hooks\require_agent_model.ps1`"" }
            }
            if (-not $document.hooks.ContainsKey($eventName)) { $document.hooks[$eventName] = @() }
            $document.hooks[$eventName] += @{ matcher = 'Agent|Bash'; hooks = $commands }
        }
        [IO.File]::WriteAllText($configPath, ($document | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    }

    & (Join-Path $repo 'deploy.ps1') -HomeDirectory $testHome -BackupDirectory $backup | Out-Null
    $firstExit = $LASTEXITCODE
    $claudeSettings = Get-Content (Join-Path $testHome '.claude\settings.json') -Raw | ConvertFrom-Json
    $codexHooks = Get-Content (Join-Path $testHome '.codex\hooks.json') -Raw | ConvertFrom-Json
    $configText = Get-Content (Join-Path $testHome '.codex\config.toml') -Raw
    $preserved = $claudeSettings.theme -eq 'dark' -and
        (@($claudeSettings.hooks.PreToolUse.hooks.command) -contains 'user-owned-hook --check' -or
         @($claudeSettings.hooks.PreToolUse | ForEach-Object { $_.hooks.command }) -contains 'user-owned-hook --check') -and
        @($codexHooks.hooks.SessionStart | ForEach-Object { $_.hooks.command }) -contains 'user-session-hook' -and
        $configText -eq "[features]`r`nhooks = false`r`n"
    Assert-True ($firstExit -eq 0 -and $preserved) 'AIRules管理外の既存設定・HookとCodex config.tomlを保持する'

    foreach ($document in @($claudeSettings, $codexHooks)) {
        foreach ($eventName in @('PreToolUse', 'UserPromptSubmit', 'Stop')) {
            $commands = @($document.hooks.$eventName | ForEach-Object { $_.hooks.command })
            $retired = @($commands | Where-Object { $_ -like "*$testHome*workflow_gate.ps1*" -or $_ -like "*$testHome*require_agent_model.ps1*" })
            Assert-True ($retired.Count -eq 0 -and $commands -contains "user-$eventName-hook" -and
                $commands -contains 'pwsh -NoProfile -File "D:\user-hooks\workflow_gate.ps1"') "$eventName の旧登録だけ解除し同居・同名ユーザーHookを保持する"
        }
    }
    Assert-True (@($claudeSettings.hooks.UserPromptSubmit | ForEach-Object { $_.hooks.command }) -contains
        "powershell -File `"$testHome\.claude\hooks\read_progress.ps1`"") 'Claudeの進捗Hookは継続する'
    $deployedHook = Invoke-Hook (Join-Path $testHome '.codex\hooks\workflow_gate.ps1') @{ hook_event_name = 'PreToolUse'; tool_name = 'Agent' }
    $oldHookBackups = @(Get-ChildItem -LiteralPath $backup -Recurse -Filter '*hooks-workflow_gate.ps1' -File)
    Assert-True ($deployedHook.ExitCode -eq 0 -and $deployedHook.Text -eq '' -and $oldHookBackups.Count -eq 2 -and
        @($oldHookBackups | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match "throw 'old gate'" }).Count -eq 2) '旧Hook本体はバックアップ後に無動作化し残存セッションからの呼出も通る'

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

    $freshHome = Join-Path $testRoot 'fresh-home'
    & (Join-Path $repo 'deploy.ps1') -HomeDirectory $freshHome -BackupDirectory (Join-Path $testRoot 'fresh-backup') | Out-Null
    $freshExit = $LASTEXITCODE
    $freshHooks = Get-Content -LiteralPath (Join-Path $freshHome '.codex\hooks.json') -Raw | ConvertFrom-Json
    Assert-True ($freshExit -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $freshHome '.codex\config.toml')) -and
        @($freshHooks.hooks.PreToolUse).Count -eq 0 -and @($freshHooks.hooks.Stop).Count -eq 0) '新規配備でも選択ゲートとCodex設定を作成しない'

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
