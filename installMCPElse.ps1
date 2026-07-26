# MCP・補助ツール導入スクリプト
# PM Skills、Unity CLI、CoplayDev/unity-mcp、ahujasid/blender-mcp を必要に応じて導入する。

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("All", "PmSkills", "UnityCli", "UnityMcp", "BlenderMcp")]
    [string]$Component = "All",

    [ValidateSet("Both", "Codex", "Claude")]
    [string]$Target = "Both",

    [switch]$ReplaceExistingMcp
)

$ErrorActionPreference = "Stop"

$pmSkillPlugins = @(
    "pm-toolkit",
    "pm-product-strategy",
    "pm-product-discovery",
    "pm-market-research",
    "pm-data-analytics",
    "pm-marketing-growth",
    "pm-go-to-market",
    "pm-execution",
    "pm-ai-shipping"
)

$script:mcpBackupPath = $null

function Invoke-ExternalCommandBestEffort {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [Parameter(Mandatory)] [string]$Description
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Description を完了できませんでした（exit code: $LASTEXITCODE）。"
        return $false
    }

    return $true
}

function Test-PluginInstalled {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string]$Plugin
    )

    $output = & $Command "plugin" "list" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Command の導入済みプラグイン一覧を取得できませんでした（exit code: $LASTEXITCODE）。"
        return $false
    }

    return [bool]($output | Select-String -SimpleMatch "$Plugin@pm-skills")
}

function Install-CodexPmSkills {
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Write-Warning "Codex CLIが見つからないため、Codex向けPM Skills導入をスキップします。"
        return
    }

    Write-Host "=== PM Skills: Codex CLI ==="
    $missingPlugins = @($pmSkillPlugins | Where-Object { -not (Test-PluginInstalled "codex" $_) })
    if ($missingPlugins.Count -eq 0) {
        Write-Host "  PM Skillsはすべて導入済みです。"
        return
    }

    if (-not $PSCmdlet.ShouldProcess("Codex CLI", "PM Skills Marketplaceを登録して不足プラグインを導入")) {
        return
    }

    Invoke-ExternalCommandBestEffort "codex" @("plugin", "marketplace", "add", "phuryn/pm-skills") "Codex Marketplace登録" | Out-Null
    foreach ($plugin in $missingPlugins) {
        Invoke-ExternalCommandBestEffort "codex" @("plugin", "add", "$plugin@pm-skills") "Codex plugin $plugin の導入" | Out-Null
    }
}

function Install-ClaudePmSkills {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Warning "Claude Code CLIが見つからないため、Claude向けPM Skills導入をスキップします。"
        return
    }

    Write-Host "=== PM Skills: Claude Code ==="
    $missingPlugins = @($pmSkillPlugins | Where-Object { -not (Test-PluginInstalled "claude" $_) })
    if ($missingPlugins.Count -eq 0) {
        Write-Host "  PM Skillsはすべて導入済みです。"
        return
    }

    if (-not $PSCmdlet.ShouldProcess("Claude Code CLI", "PM Skills Marketplaceを登録して不足プラグインを導入")) {
        return
    }

    Invoke-ExternalCommandBestEffort "claude" @("plugin", "marketplace", "add", "phuryn/pm-skills") "Claude Marketplace登録" | Out-Null
    foreach ($plugin in $missingPlugins) {
        Invoke-ExternalCommandBestEffort "claude" @("plugin", "install", "$plugin@pm-skills") "Claude plugin $plugin の導入" | Out-Null
    }
}

function Install-PmSkills {
    switch ($Target) {
        "Codex" { Install-CodexPmSkills }
        "Claude" { Install-ClaudePmSkills }
        "Both" {
            Install-CodexPmSkills
            Install-ClaudePmSkills
        }
    }

    Write-Host "=== PM Skills導入完了: $Target ==="
}

function Install-UnityCli {
    if (Get-Command unity -ErrorAction SilentlyContinue) {
        $version = & unity --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Unity CLIは導入済みです: $version"
        } else {
            Write-Host "  Unity CLIは導入済みです。"
        }
        return
    }

    Write-Host "=== Unity CLI: install ==="
    if (-not $PSCmdlet.ShouldProcess("Unity CLI", "betaチャネルから導入")) {
        return
    }

    try {
        # Unity公式の導入手順。betaはUnity Pipelineを含む最新の実験的CLIチャネル。
        $env:UNITY_CLI_CHANNEL = "beta"
        $installer = Invoke-RestMethod "https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.ps1"
        Invoke-Expression $installer
        Write-Host "  Unity CLIを導入しました。新しいターミナルを開いて 'unity --version' を確認してください。"
    } catch {
        Write-Warning "Unity CLIの導入に失敗しました: $($_.Exception.Message)"
    }
}

function Get-McpRegistration {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [Parameter(Mandatory)] [string]$ServerName
    )

    $output = & $Command @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($exitCode -eq 0) {
        return [pscustomobject]@{ State = "Exists"; Output = $text }
    }

    if ($text -match "(?i)(not found|does not exist|no .*named)") {
        return [pscustomobject]@{ State = "Missing"; Output = $text }
    }

    Write-Warning "$Command mcp get $ServerName の結果を安全に判定できませんでした（exit code: $exitCode）。登録を変更しません。"
    return [pscustomobject]@{ State = "Unknown"; Output = $text }
}

function Test-McpConfiguration {
    param(
        [Parameter(Mandatory)] [string]$Output,
        [Parameter(Mandatory)] [string]$ExpectedCommand,
        # 期待するargsトークン列。表示形式差を吸収するため、順序を保った空白1個区切りで比較する。
        [Parameter(Mandatory)] [string[]]$ExpectedArguments
    )

    $expectedArgumentLine = $ExpectedArguments -join " "
    $commandMatch = [regex]::Match($Output, "(?im)^\s*command\s*:\s*(.+?)\s*$")
    $argumentsMatch = [regex]::Match($Output, "(?im)^\s*args?\s*:\s*(.+?)\s*$")
    if ($commandMatch.Success -and $argumentsMatch.Success) {
        $actualCommand = $commandMatch.Groups[1].Value.Trim()
        $actualArguments = ($argumentsMatch.Groups[1].Value.Trim() -split "\s+") -join " "
        return $actualCommand -eq $ExpectedCommand -and $actualArguments -eq $expectedArgumentLine
    }

    $tokens = @($ExpectedCommand) + $ExpectedArguments
    $pattern = "(?im)^\s*" + (($tokens | ForEach-Object { [regex]::Escape($_) }) -join "\s+") + "\s*$"
    return $Output -match $pattern
}

function Show-McpDifference {
    param(
        [Parameter(Mandatory)] [string]$ClientName,
        [Parameter(Mandatory)] [string]$ServerName,
        [Parameter(Mandatory)] [string]$SourceName,
        [Parameter(Mandatory)] [string]$ExistingConfiguration,
        [Parameter(Mandatory)] [string]$DesiredCommand
    )

    Write-Warning "$ClientName の $ServerName は同名ですが、$SourceName の設定と一致しません。"
    Write-Host "  既存: $ExistingConfiguration"
    Write-Host "  希望: $DesiredCommand"
}

function Backup-McpConfiguration {
    if ($script:mcpBackupPath) {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:mcpBackupPath = Join-Path $env:LOCALAPPDATA "AIRules\backup\$timestamp"
    New-Item -ItemType Directory -Path $script:mcpBackupPath -Force | Out-Null

    $configFiles = @(
        (Join-Path $HOME ".codex\config.toml"),
        (Join-Path $HOME ".claude.json")
    )
    foreach ($configFile in $configFiles) {
        if (Test-Path -LiteralPath $configFile) {
            Copy-Item -LiteralPath $configFile -Destination $script:mcpBackupPath
        } else {
            Write-Warning "バックアップ対象が見つかりません: $configFile"
        }
    }

    Write-Host "  MCP設定をバックアップしました: $script:mcpBackupPath"
}

function Install-McpForClient {
    param(
        [Parameter(Mandatory)] [string]$ClientName,
        [Parameter(Mandatory)] [string]$ServerName,
        [Parameter(Mandatory)] [string]$SourceName,
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string[]]$GetArguments,
        [Parameter(Mandatory)] [string[]]$AddArguments,
        [Parameter(Mandatory)] [string[]]$RemoveArguments,
        [Parameter(Mandatory)] [string]$ExpectedCommand,
        [Parameter(Mandatory)] [string[]]$ExpectedArguments,
        [Parameter(Mandatory)] [string]$DesiredCommand
    )

    $registration = Get-McpRegistration $Command $GetArguments $ServerName
    if ($registration.State -eq "Unknown") {
        return
    }

    $replace = $false
    if ($registration.State -eq "Exists") {
        if (Test-McpConfiguration $registration.Output $ExpectedCommand $ExpectedArguments) {
            Write-Host "  $ClientName の $ServerName は $SourceName として登録済みです。"
            return
        }

        Show-McpDifference $ClientName $ServerName $SourceName $registration.Output $DesiredCommand
        if (-not $ReplaceExistingMcp) {
            # 既存登録を黙って残したまま成功扱いにすると、利用者は登録済みだと誤解する。
            # 上書きは破壊的なので自動では行わず、明示指定を促して停止する。
            throw "$ClientName に別内容の $ServerName MCP が登録済みです。上書きするには -ReplaceExistingMcp を明示指定してください。"
        }
        $replace = $true
    }

    $action = if ($replace) { "既存の $ServerName MCP登録を置換" } else { "$ServerName MCPを登録" }
    if (-not $PSCmdlet.ShouldProcess($ClientName, $action)) {
        return
    }

    Backup-McpConfiguration
    if ($replace) {
        if (-not (Invoke-ExternalCommandBestEffort $Command $RemoveArguments "$ClientName $ServerName MCP登録の削除")) {
            return
        }
    }
    Invoke-ExternalCommandBestEffort $Command $AddArguments "$ClientName $SourceName の登録" | Out-Null
}

function Install-UnityMcp {
    Write-Host "=== UnityMCP: CoplayDev/unity-mcp ==="
    $uvx = Get-Command uvx -ErrorAction SilentlyContinue
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    $claude = Get-Command claude -ErrorAction SilentlyContinue

    if (-not $uvx) {
        # サーバ本体はPyPIのmcpforunityserverをuvxが実行時取得するため、uvxが無いと登録しても起動しない。
        Write-Warning "uvx が見つからないため、UnityMCP導入をスキップします。"
        return
    }

    $serverArguments = @("--from", "mcpforunityserver", "mcp-for-unity", "--transport", "stdio")
    $common = @{
        ServerName        = "unityMCP"
        SourceName        = "CoplayDev/unity-mcp"
        ExpectedCommand   = "uvx"
        ExpectedArguments = $serverArguments
    }

    if (-not $codex) {
        Write-Warning "Codex CLIが見つからないため、Codex向けUnityMCP登録をスキップします。"
    } else {
        Install-McpForClient @common `
            -ClientName "Codex CLI" -Command "codex" `
            -GetArguments @("mcp", "get", "unityMCP") `
            -AddArguments (@("mcp", "add", "unityMCP", "--", "uvx") + $serverArguments) `
            -RemoveArguments @("mcp", "remove", "unityMCP") `
            -DesiredCommand "codex mcp add unityMCP -- uvx $($serverArguments -join ' ')"
    }
    if (-not $claude) {
        Write-Warning "Claude Code CLIが見つからないため、Claude向けUnityMCP登録をスキップします。"
    } else {
        # Claudeは既定scopeがlocalのため --scope user を付ける。
        Install-McpForClient @common `
            -ClientName "Claude Code" -Command "claude" `
            -GetArguments @("mcp", "get", "unityMCP") `
            -AddArguments (@("mcp", "add", "--scope", "user", "--transport", "stdio", "unityMCP", "--", "uvx") + $serverArguments) `
            -RemoveArguments @("mcp", "remove", "unityMCP") `
            -DesiredCommand "claude mcp add --scope user --transport stdio unityMCP -- uvx $($serverArguments -join ' ')"
    }

    Write-Host ""
    Write-Host "Unity側は対象projectのPackage Managerへ https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity を追加し、Window → MCP for Unity で接続を確認してください。"
    Write-Warning "MCP for UnityはEditorのAsset・Sceneを変更できます。対象projectをGit管理下に置いてから利用してください。"
}

function Install-BlenderMcp {
    Write-Host "=== BlenderMCP: ahujasid/blender-mcp ==="
    $uvx = Get-Command uvx -ErrorAction SilentlyContinue
    $blender = Get-Command blender -ErrorAction SilentlyContinue
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    $claude = Get-Command claude -ErrorAction SilentlyContinue

    if (-not $uvx) {
        Write-Warning "uvx が見つかりません。"
    }
    if (-not $blender) {
        Write-Warning "Blender が見つかりません。"
    }
    if (-not $codex) {
        Write-Warning "Codex CLIが見つかりません。"
    }
    if (-not $claude) {
        Write-Warning "Claude Code CLIが見つかりません。"
    }
    if (-not $uvx -or -not $blender) {
        Write-Warning "uvx または Blender が見つからないため、BlenderMCP導入をスキップします。"
        return
    }
    $common = @{
        ServerName        = "blender"
        SourceName        = "ahujasid/blender-mcp"
        ExpectedCommand   = "uvx"
        ExpectedArguments = @("blender-mcp")
    }

    if (-not $codex) {
        Write-Warning "Codex CLIが見つからないため、Codex向けBlenderMCP登録をスキップします。"
    } else {
        Install-McpForClient @common `
            -ClientName "Codex CLI" -Command "codex" `
            -GetArguments @("mcp", "get", "blender") `
            -AddArguments @("mcp", "add", "blender", "--", "uvx", "blender-mcp") `
            -RemoveArguments @("mcp", "remove", "blender") `
            -DesiredCommand "codex mcp add blender -- uvx blender-mcp"
    }
    if (-not $claude) {
        Write-Warning "Claude Code CLIが見つからないため、Claude向けBlenderMCP登録をスキップします。"
    } else {
        # Claudeは既定scopeがlocalのため --scope user を付ける。
        Install-McpForClient @common `
            -ClientName "Claude Code" -Command "claude" `
            -GetArguments @("mcp", "get", "blender") `
            -AddArguments @("mcp", "add", "--scope", "user", "--transport", "stdio", "blender", "--", "uvx", "blender-mcp") `
            -RemoveArguments @("mcp", "remove", "blender") `
            -DesiredCommand "claude mcp add --scope user --transport stdio blender -- uvx blender-mcp"
    }

    Write-Host ""
    Write-Host "Blender Add-onはGUIで有効化し、BlenderMCPパネルの Connect を手動で実行してください。"
    Write-Warning "BlenderMCPには任意コード実行機能とテレメトリ設定があります。利用前に設定内容を確認してください。"
}

switch ($Component) {
    "PmSkills" { Install-PmSkills }
    "UnityCli" { Install-UnityCli }
    "UnityMcp" { Install-UnityMcp }
    "BlenderMcp" { Install-BlenderMcp }
    "All" {
        Install-PmSkills
        Install-UnityCli
        Install-UnityMcp
        Install-BlenderMcp
    }
}
