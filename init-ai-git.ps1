```powershell
# init-ai-git.ps1

# ==========================================================
# AI Git Initialization
# - Select SSH key
# - Configure Git SSH key
# - Verify GitHub CLI
# - Verify GitHub CLI authentication
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
# GitHub Account
# ----------------------------------------------------------

do {
    $GitHubUser = Read-Host "GitHub account name"
} while ([string]::IsNullOrWhiteSpace($GitHubUser))

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

    $valid =
        [int]::TryParse($input, [ref]$null) -and
        ([int]$input -ge 1) -and
        ([int]$input -le $keys.Count)

    if (-not $valid) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }

} until ($valid)

$KeyPath = $keys[[int]$input - 1].FullName

Write-Host ""
Write-Host "Using SSH Key: $($keys[[int]$input - 1].Name)" -ForegroundColor Green

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
# GitHub CLI Authentication Check
# ----------------------------------------------------------

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "GitHub CLI authentication is invalid." -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""

    Write-Host "Git operations using SSH will work." -ForegroundColor Yellow
    Write-Host "However, GitHub API operations such as:" -ForegroundColor Yellow
    Write-Host "  - gh pr create"
    Write-Host "  - gh pr view"
    Write-Host "  - gh issue create"
    Write-Host "will fail until authentication is restored."
    Write-Host ""

    Write-Host "Please run the following commands once:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    gh auth logout -h github.com -u $GitHubUser"
    Write-Host "    gh auth login -h github.com"
    Write-Host ""

    exit 1
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
```
