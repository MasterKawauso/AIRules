# AIRULES-MANAGED-HOOK schema=1 source=Claude/hooks/read_progress.ps1
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$f = Join-Path $PWD "PROGRESS.md"
if (Test-Path $f) {
    $content = [System.IO.File]::ReadAllText($f)
    $obj = @{
        hookSpecificOutput = @{
            hookEventName   = "UserPromptSubmit"
            additionalContext = "[PROGRESS.md - review before starting work]`n$content"
        }
    }
    $obj | ConvertTo-Json -Compress
}
