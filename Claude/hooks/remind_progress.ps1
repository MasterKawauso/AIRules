# AIRULES-MANAGED-HOOK schema=1 source=Claude/hooks/remind_progress.ps1
$obj = @{
    systemMessage = "Reminder: Update PROGRESS.md with today's work log before finishing."
}
$obj | ConvertTo-Json -Compress
