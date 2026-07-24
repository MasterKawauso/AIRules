# Unity CLI 導入スクリプト
# Unity公式のベータチャネルから、Unity EditorをCLIで操作する unity コマンドを導入する。
# 原典: https://docs.unity.com/en-us/hub/use-unity-cli

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

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
try {
    # Unity公式の導入手順。betaはUnity Pipelineを含む最新の実験的CLIチャネル。
    $env:UNITY_CLI_CHANNEL = "beta"
    $installer = Invoke-RestMethod "https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.ps1"
    Invoke-Expression $installer
    Write-Host "  Unity CLIを導入しました。新しいターミナルを開いて 'unity --version' を確認してください。"
} catch {
    Write-Warning "Unity CLIの導入に失敗しました: $($_.Exception.Message)"
}
