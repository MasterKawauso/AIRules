# phuryn/pm-skills 導入スクリプト
# 公式MarketplaceをCodex CLI / Claude Codeへ登録し、9プラグインを導入する。
# 原典: https://github.com/phuryn/pm-skills (MIT License)

[CmdletBinding()]
param(
    [ValidateSet("Both", "Codex", "Claude")]
    [string]$Target = "Both"
)

$ErrorActionPreference = "Stop"

$plugins = @(
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

function Invoke-ExternalCommandBestEffort {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [Parameter(Mandatory)] [string]$Description
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Description を完了できませんでした（exit code: $LASTEXITCODE）。既に導入済みの場合は無視できます。"
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
    $missingPlugins = @($plugins | Where-Object { -not (Test-PluginInstalled "codex" $_) })
    if ($missingPlugins.Count -eq 0) {
        Write-Host "  PM Skillsはすべて導入済みです。"
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
    $missingPlugins = @($plugins | Where-Object { -not (Test-PluginInstalled "claude" $_) })
    if ($missingPlugins.Count -eq 0) {
        Write-Host "  PM Skillsはすべて導入済みです。"
        return
    }

    Invoke-ExternalCommandBestEffort "claude" @("plugin", "marketplace", "add", "phuryn/pm-skills") "Claude Marketplace登録" | Out-Null
    foreach ($plugin in $missingPlugins) {
        Invoke-ExternalCommandBestEffort "claude" @("plugin", "install", "$plugin@pm-skills") "Claude plugin $plugin の導入" | Out-Null
    }
}

switch ($Target) {
    "Codex"  { Install-CodexPmSkills }
    "Claude" { Install-ClaudePmSkills }
    "Both" {
        Install-CodexPmSkills
        Install-ClaudePmSkills
    }
}

Write-Host "=== PM Skills導入完了: $Target ==="
