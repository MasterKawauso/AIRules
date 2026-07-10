# init-ai-git.ps1

# ==========================================================
# AI Git Initialization
# - Select SSH key
# - Configure Git SSH key
# - Verify GitHub CLI
# - Auto re-authenticate GitHub CLI if needed
# ==========================================================

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------
# Git Repository Check
# ----------------------------------------------------------

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Current directory is not a Git repository." -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------
# SSH Key Selection
# ----------------------------------------------------------

$sshDir = Join-Path $HOME ".ssh"

$keys = Get-ChildItem $sshDir -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -ne ".pub" -and
        $_.Name -notin @(
            "known_hosts",
            "known_hosts.old",
            "config"
        )
    }

if ($keys.Count -eq 0) {
    Write-Host "Error: No SSH private keys found." -ForegroundColor Red
    Write-Host "Search path: $sshDir"
    exit 1
}

Write-Host ""
Write-Host "Available SSH Keys:" -ForegroundColor Cyan

for ($i = 0; $i -lt $keys.Count; $i++) {
    Write-Host ("[{0}] {1}" -f ($i + 1), $keys[$i].Name)
}

do {
    $input = Read-Host "Select SSH key number"

    $selectedNumber = 0
    $valid =
        [int]::TryParse($input, [ref]$selectedNumber) -and
        ($selectedNumber -ge 1) -and
        ($selectedNumber -le $keys.Count)

    if (-not $valid) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }

} until ($valid)

$KeyPath = $keys[$selectedNumber - 1].FullName

Write-Host ""
Write-Host "Using SSH Key: $($keys[$selectedNumber - 1].Name)" -ForegroundColor Green

# ----------------------------------------------------------
# Configure Git SSH
# ----------------------------------------------------------

$SshCommand = "ssh -i `"$KeyPath`" -o IdentitiesOnly=yes"
git config --local core.sshCommand $SshCommand

Write-Host ""
Write-Host "Git SSH configuration completed." -ForegroundColor Green
Write-Host "Current core.sshCommand:"
git config --local --get core.sshCommand

# ----------------------------------------------------------
# GitHub CLI Check
# ----------------------------------------------------------

gh --version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Error: GitHub CLI (gh) is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------
# GitHub CLI Authentication Check / Auto Re-login
# ----------------------------------------------------------

gh auth status -h github.com *> $null
if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "GitHub CLI authentication is invalid." -ForegroundColor Yellow
    Write-Host "Re-authentication will be started." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Logging out from github.com..." -ForegroundColor Cyan

    gh auth logout -h github.com
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Warning: gh auth logout failed or was cancelled." -ForegroundColor Yellow
        Write-Host "Continuing to login anyway."
    }

    Write-Host ""
    Write-Host "Starting GitHub CLI login..." -ForegroundColor Cyan
    Write-Host "Please select the GitHub account you want to use." -ForegroundColor Cyan
    Write-Host ""

    gh auth login -h github.com
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Error: GitHub CLI login failed." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "Re-checking GitHub CLI authentication..." -ForegroundColor Cyan

    gh auth status -h github.com *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Error: GitHub CLI authentication is still invalid." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "GitHub CLI authentication OK." -ForegroundColor Green

# ----------------------------------------------------------
# Completed
# ----------------------------------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "AI Git initialization completed." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green