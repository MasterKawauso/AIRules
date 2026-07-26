$obj = @{
    systemMessage = "Reminder: Update PROGRESS.md with today's work log before finishing."
}
$obj | ConvertTo-Json -Compress
