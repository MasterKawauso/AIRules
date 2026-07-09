# AIRules 配備スクリプト
# 正本はこのリポジトリ。配備先 (~/.codex, ~/.claude) を直接編集しないこと。
# 使い方: リポジトリのファイルを編集したら .\deploy.ps1 を実行する。
# 既存の配備先ファイルは backup\<日時>\ へ退避してから上書きする。

$ErrorActionPreference = "Stop"

$repo       = $PSScriptRoot
$stamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot = Join-Path $repo "backup\$stamp"
$codexHome  = Join-Path $HOME ".codex"
$claudeHome = Join-Path $HOME ".claude"

$header = "<!-- AUTO-GENERATED from $repo : 直接編集せず、リポジトリを編集して deploy.ps1 を再実行すること -->"

function Backup-IfExists {
    param([string]$Path)
    if (Test-Path $Path) {
        if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Force $backupRoot | Out-Null }
        $name = ($Path -replace '[:\\/]', '_')
        Copy-Item $Path (Join-Path $backupRoot $name) -Recurse -Force
    }
}

# Markdown用: 先頭にAUTO-GENERATEDヘッダーを付けて配備
function Deploy-WithHeader {
    param([string]$Src, [string]$Dst)
    Backup-IfExists $Dst
    $dir = Split-Path $Dst
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $content = Get-Content $Src -Raw
    Set-Content -Path $Dst -Value ($header + "`r`n`r`n" + $content) -Encoding utf8
    Write-Host "  deployed: $Dst"
}

# frontmatter必須ファイル用: ヘッダーを付けずそのまま配備（--- が先頭行である必要があるため）
function Deploy-Raw {
    param([string]$Src, [string]$Dst)
    Backup-IfExists $Dst
    $dir = Split-Path $Dst
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    Copy-Item $Src $Dst -Force
    Write-Host "  deployed: $Dst"
}

Write-Host "=== AIRules deploy ($stamp) ==="

# 1. AGENTS.md（共通正本）
Deploy-WithHeader (Join-Path $repo "AGENTS.md") (Join-Path $codexHome "AGENTS.md")
Deploy-WithHeader (Join-Path $repo "AGENTS.md") (Join-Path $claudeHome "AGENTS.md")

# 2. airules/（用途別ルール）
Get-ChildItem (Join-Path $repo "airules") -Filter *.md | ForEach-Object {
    Deploy-WithHeader $_.FullName (Join-Path $codexHome "airules\$($_.Name)")
    Deploy-WithHeader $_.FullName (Join-Path $claudeHome "airules\$($_.Name)")
}

# 3. Claude 入口 + サブエージェント定義 + 出力スタイル
Deploy-WithHeader (Join-Path $repo "Claude\CLAUDE.md") (Join-Path $claudeHome "CLAUDE.md")
Get-ChildItem (Join-Path $repo "Claude\agents") -Filter *.md | ForEach-Object {
    Deploy-Raw $_.FullName (Join-Path $claudeHome "agents\$($_.Name)")
}
Get-ChildItem (Join-Path $repo "Claude\output-styles") -Filter *.md | ForEach-Object {
    Deploy-Raw $_.FullName (Join-Path $claudeHome "output-styles\$($_.Name)")
}

# 4. 旧構成ファイル（~/.claude/skills/ の旧ルール）をバックアップへ退避
$oldSkills = @("unity.md", "UnrealEngine.md", "REVIEW.md", "GAME_COMMON_MODULE.md")
foreach ($f in $oldSkills) {
    $p = Join-Path $claudeHome "skills\$f"
    if (Test-Path $p) {
        Backup-IfExists $p
        Remove-Item $p -Force
        Write-Host "  retired old skill: $p"
    }
}

Write-Host ""
if (Test-Path $backupRoot) {
    Write-Host "=== 完了。バックアップ: $backupRoot ==="
} else {
    Write-Host "=== 完了（既存ファイルがなかったためバックアップは作成されていません） ==="
}
