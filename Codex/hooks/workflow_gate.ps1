# AIRULES-MANAGED-HOOK schema=1 source=Codex/hooks/workflow_gate.ps1
# Shared PreToolUse/UserPromptSubmit/Stop gate for Claude Code and Codex.
# The gate records only classification state; prompts and transcripts are not copied.
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-JsonResult {
    param([hashtable]$Value)
    $Value | ConvertTo-Json -Compress -Depth 8
    exit 0
}

function Get-PropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Get-StateRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:AIRULES_WORKFLOW_STATE_ROOT)) {
        return $env:AIRULES_WORKFLOW_STATE_ROOT
    }
    $base = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $env:LOCALAPPDATA
    } else {
        [IO.Path]::GetTempPath()
    }
    return (Join-Path $base 'AIRules\workflow-gate')
}

function Get-StatePath {
    param([string]$SessionId)
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $null }
    $bytes = [Text.Encoding]::UTF8.GetBytes($SessionId)
    $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '').ToLowerInvariant()
    return (Join-Path (Get-StateRoot) "$hash.json")
}

function Read-State {
    param([string]$SessionId)
    $path = Get-StatePath $SessionId
    if ($null -eq $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        if ($state.schemaVersion -ne 1 -or $state.sessionId -ne $SessionId) { return $null }
        return $state
    } catch {
        return $null
    }
}

function Write-State {
    param([hashtable]$State)
    $path = Get-StatePath ([string]$State.sessionId)
    if ($null -eq $path) { return $false }
    try {
        $root = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $root)) {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
        }
        $temporary = "$path.$PID.tmp"
        [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $path -Force
        return $true
    } catch {
        return $false
    }
}

function Test-NewWorkUnit {
    param([string]$Text)
    return $Text -match '(?i)(別件|別の依頼|新しい依頼|次のタスク|新規タスク|new\s+task|separate\s+task)'
}

function Test-ExplicitSelection {
    param([string]$Text, [hashtable]$ExistingState)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    if ($Text -match '(?im)^\s*AIRULES_WORKFLOW_SELECTION:\s*owner=(Codex|Claude|current);\s*model=([A-Za-z0-9._-]+);\s*thinking=(low|medium|high|xhigh|max|ultra);\s*scope=.+$') {
        return $true
    }
    if ($Text -match '(?i)(現在|今|起動中).{0,12}(AI|Codex|Claude).{0,40}(そのまま|続行|進め)' -and
        $Text -match '(?i)(確認.{0,8}(不要|待たない|省略)|確認待ちにしない|proceed\s+without\s+confirmation)') {
        return $true
    }

    $hasOwner = $Text -match '(?i)(担当\s*(AI)?\s*[:：=]?\s*(Codex|Claude)|owner\s*[:=]\s*(Codex|Claude)|現在のAI|current\s+(AI|agent))'
    $hasModel = $Text -match '(?i)(モデル\s*[:：=]\s*\S+|model\s*[:=]\s*[A-Za-z0-9._-]+|\b(opus|sonnet|haiku|fable|gpt-[A-Za-z0-9._-]+)\b)'
    $hasThinking = $Text -match '(?i)(思考深度\s*[:：=]?\s*(低|中|高|low|medium|high|xhigh|max|ultra)|reasoning(_effort)?\s*[:=]\s*(low|medium|high|xhigh|max|ultra)|effort\s*[:=]\s*(low|medium|high|xhigh|max|ultra))'
    if ($hasOwner -and $hasModel -and $hasThinking) { return $true }

    if ($null -ne $ExistingState -and $ExistingState.status -eq 'pending' -and
        $ExistingState.recommendationPresented -eq $true -and $Text.Length -le 120) {
        return $Text.Trim() -match '(?i)^(推奨案|その案|それ|おすすめ|recommended)(で|を)?(そのまま)?(進めて(ください)?|お願いします|採用|承認|ok|okay|proceed)?[。.!！]?$|^(ok|okay|yes|proceed)[。.!！]?$'
    }
    return $false
}

function Test-NegatedTerm {
    param([string]$Text, [string]$Term)
    $escaped = [regex]::Escape($Term)
    return ($Text -match "(?i)$escaped.{0,18}(変更しない|変えない|触らない|対象外|維持|禁止)") -or
        ($Text -match "(?i)(without\s+changing|do\s+not\s+(change|touch)|keep).{0,24}$escaped")
}

function Get-WorkflowClassification {
    param([string]$Text)
    $result = [ordered]@{ Required = $false; Reasons = @(); ResponsibilityCount = 0 }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }

    $change = $Text -match '(?i)(実装|修正|変更|追加|削除|移行|更新|作成|構築|導入|置換|リファクタ|直して|fix|implement|change|add|remove|migrate|update|create|build|refactor)'
    $design = $Text -match '(?i)(設計|アーキテクチャ|責務分割|依存方向|状態遷移|公開境界|design|architecture)'
    $delegation = $Text -match '(?i)(Sub\s*Agent|サブエージェント|複数AI|別AI|委譲|並列作業|並列実装|相互レビュー|multi-agent|delegate)'
    if (-not ($change -or $design -or $delegation)) { return $result }

    $reasons = [Collections.Generic.List[string]]::new()
    $hardTerms = [ordered]@{
        'Public API変更' = @('Public API', '公開API')
        'データ構造・スキーマ変更' = @('データ構造', 'schema', 'スキーマ', 'データ移行', 'database migration')
        '外部依存変更' = @('外部依存', '外部ライブラリ', 'dependency', 'package追加', 'SDK追加')
        'エンジン設定変更' = @('エンジン設定', 'Project Settings', 'Build Settings', 'Tags and Layers', 'project.godot')
        '広範囲・高リスク変更' = @('広範囲', '大規模', '高リスク', '破壊的変更', 'security', 'セキュリティ', '認証', '権限')
    }
    foreach ($reason in $hardTerms.Keys) {
        foreach ($term in $hardTerms[$reason]) {
            if (($change -or $design) -and $Text -match [regex]::Escape($term) -and -not (Test-NegatedTerm $Text $term)) {
                $reasons.Add($reason)
                break
            }
        }
    }

    $categories = [ordered]@{
        api = '(?i)(API|endpoint|公開メソッド|public\s+(method|class|interface))'
        data = '(?i)(データ|状態|保存|DB|database|schema|スキーマ|serialize|model)'
        domain = '(?i)(ドメイン|業務ロジック|gameplay|ゲームロジック|service|usecase)'
        presentation = '(?i)(UI|UX|画面|表示|presentation|view|frontend)'
        engine = '(?i)(Scene|Prefab|Editor|Inspector|Unity|Unreal|Godot|Blueprint)'
        infrastructure = '(?i)(設定|config|build|CI|deploy|依存|package|SDK|infrastructure)'
        integration = '(?i)(network|通信|RPC|MCP|外部サービス|integration)'
    }
    $categoryCount = 0
    foreach ($pattern in $categories.Values) {
        if ($Text -match $pattern) { $categoryCount++ }
    }
    $result.ResponsibilityCount = $categoryCount

    $minor = $Text -match '(?i)(軽微|単一ファイル|1ファイル|one[- ]file|誤字|typo|文言修正|コメントのみ|importのみ|明確な単一変更)'
    if ($design -and -not $minor) { $reasons.Add('設計判断を含む変更') }
    if (($change -or $design) -and $categoryCount -ge 2) { $reasons.Add('複数責務変更') }
    if ($delegation) {
        $reasons.Add('担当・モデル選択で品質・費用・時間が変わる分担')
    }

    $uniqueReasons = @($reasons | Select-Object -Unique)
    if ($minor -and $uniqueReasons.Count -eq 0) { return $result }
    $result.Reasons = $uniqueReasons
    $result.Required = $uniqueReasons.Count -gt 0
    return $result
}

function Get-DocumentSelection {
    param([string]$Cwd)
    foreach ($name in @('PLAN.md', 'SESSION.md')) {
        $path = Join-Path $Cwd $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $text = Get-Content -LiteralPath $path -Raw
            if ($text -match '(?im)^\s*AIRULES_WORKFLOW_SELECTION:\s*owner=(Codex|Claude|current);\s*model=([A-Za-z0-9._-]+);\s*thinking=(low|medium|high|xhigh|max|ultra);\s*scope=(.+?)\s*$') {
                return @{ Source = $name; Scope = $Matches[4].Trim(); Value = $Matches[0].Trim() }
            }
        } catch {
            continue
        }
    }
    return $null
}

function Get-TextContent {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        if ($item -is [string]) { $parts.Add($item); continue }
        $type = [string](Get-PropertyValue $item 'type')
        if ($type -in @('text', 'input_text')) {
            $text = [string](Get-PropertyValue $item 'text')
            if (-not [string]::IsNullOrWhiteSpace($text)) { $parts.Add($text) }
        }
    }
    return [string]::Join("`n", $parts)
}

function Get-TranscriptUserPrompts {
    param([string]$TranscriptPath)
    $prompts = [Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($TranscriptPath) -or -not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) { return @() }
    try {
        foreach ($line in Get-Content -LiteralPath $TranscriptPath -Tail 400) {
            try { $record = $line | ConvertFrom-Json } catch { continue }
            $role = [string](Get-PropertyValue $record 'role')
            $content = Get-PropertyValue $record 'content'
            if ($role -eq 'user') {
                $text = Get-TextContent $content
                if ($text) { $prompts.Add($text) }
                continue
            }
            if ((Get-PropertyValue $record 'type') -eq 'user') {
                $message = Get-PropertyValue $record 'message'
                $text = Get-TextContent (Get-PropertyValue $message 'content')
                if ($text) { $prompts.Add($text) }
                continue
            }
            $payload = Get-PropertyValue $record 'payload'
            if ((Get-PropertyValue $payload 'role') -eq 'user') {
                $text = Get-TextContent (Get-PropertyValue $payload 'content')
                if ($text) { $prompts.Add($text) }
            }
        }
    } catch {
        return @()
    }
    return @($prompts)
}

function Resolve-StateFromTranscript {
    param([object]$Payload)
    $sessionId = [string](Get-PropertyValue $Payload 'session_id')
    $cwd = [string](Get-PropertyValue $Payload 'cwd')
    $state = $null
    foreach ($prompt in Get-TranscriptUserPrompts ([string](Get-PropertyValue $Payload 'transcript_path'))) {
        if (Test-NewWorkUnit $prompt) { $state = $null }
        if (Test-ExplicitSelection $prompt $state) {
            $state = [ordered]@{ schemaVersion = 1; sessionId = $sessionId; cwd = $cwd; status = 'selected'; reasons = @(); updatedAt = [DateTime]::UtcNow.ToString('o') }
            continue
        }
        $classification = Get-WorkflowClassification $prompt
        if ($classification.Required -and ($null -eq $state -or $state.status -ne 'selected')) {
            $state = [ordered]@{ schemaVersion = 1; sessionId = $sessionId; cwd = $cwd; status = 'pending'; reasons = $classification.Reasons; updatedAt = [DateTime]::UtcNow.ToString('o') }
        }
    }
    return $state
}

function Get-EffectiveState {
    param([object]$Payload)
    $sessionId = [string](Get-PropertyValue $Payload 'session_id')
    $state = Read-State $sessionId
    if ($null -ne $state) { return $state }
    return Resolve-StateFromTranscript $Payload
}

function Test-ReadOnlyShellCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    if ($Command -match '(?i)(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|Rename-Item|apply_patch|git\s+(add|commit|push|merge|rebase|reset|checkout|switch|restore|clean)|\b(del|erase|move|copy|ren|mkdir|rmdir)\b|>>?|python.+(-c|<<)|node.+(-e)|Invoke-WebRequest.+-OutFile)') {
        return $false
    }
    return $Command -match '(?i)^\s*(Get-Content|Get-ChildItem|Get-Command|Get-Item|Test-Path|Resolve-Path|Select-String|rg\b|git\s+(status|diff|log|show|branch\s+--show-current)|codex\s+(--version|--help|features\s+list)|claude\s+(--version|--help)|where(\.exe)?\b)'
}

function Test-MutatingTool {
    param([string]$ToolName, [object]$ToolInput)
    if ($ToolName -in @('Edit', 'Write', 'NotebookEdit', 'apply_patch')) { return $true }
    if ($ToolName -in @('Bash', 'exec_command', 'shell_command')) {
        return -not (Test-ReadOnlyShellCommand ([string](Get-PropertyValue $ToolInput 'command')))
    }
    if ($ToolName -in @('Agent', 'spawn_agent')) {
        $agent = [string](Get-PropertyValue $ToolInput 'subagent_type')
        if ([string]::IsNullOrWhiteSpace($agent)) { $agent = [string](Get-PropertyValue $ToolInput 'agent_type') }
        return $agent -notin @('Explore', 'statusline-setup', 'claude-code-guide')
    }
    if ($ToolName -match '(?i)^mcp__') {
        if ($ToolName -match '(?i)__(get|list|read|search|find|query|fetch|view|inspect|open)[A-Za-z0-9_]*$') { return $false }
        return $true
    }
    return $false
}

function Test-CompliantRecommendation {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    $hasOwner = $Message -match '(?i)(担当AI|Codex|Claude)'
    $hasModel = $Message -match '(?i)(モデル|opus|sonnet|haiku|fable|gpt-[A-Za-z0-9._-]+)'
    $hasThinking = $Message -match '(?i)(思考深度|reasoning|effort|low|medium|high|xhigh|max|ultra)'
    $tradeoffCount = 0
    foreach ($pattern in @('品質|quality', '費用|cost|token', '時間|所要|速度|time|latency')) {
        if ($Message -match "(?i)$pattern") { $tradeoffCount++ }
    }
    $waitsForUser = $Message -match '(?i)(回答|選択|指定|どれ|よいですか|待ちます|確認|choose|reply|which)'
    return $hasOwner -and $hasModel -and $hasThinking -and $tradeoffCount -ge 2 -and $waitsForUser
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$eventName = [string](Get-PropertyValue $payload 'hook_event_name')
if ([string]::IsNullOrWhiteSpace($eventName)) { $eventName = [string](Get-PropertyValue $payload 'hookEventName') }
$sessionId = [string](Get-PropertyValue $payload 'session_id')
$cwd = [string](Get-PropertyValue $payload 'cwd')

if ($eventName -eq 'UserPromptSubmit') {
    $prompt = [string](Get-PropertyValue $payload 'prompt')
    $existing = Read-State $sessionId
    if (Test-NewWorkUnit $prompt) {
        $existing = [ordered]@{ schemaVersion = 1; sessionId = $sessionId; cwd = $cwd; status = 'none'; reasons = @(); updatedAt = [DateTime]::UtcNow.ToString('o') }
        $null = Write-State $existing
    }

    $documentSelection = Get-DocumentSelection $cwd
    $documentSelectionApplies = $null -ne $documentSelection -and (
        $prompt.IndexOf([string]$documentSelection.Scope, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $prompt -match '(?i)(PLAN\.md|SESSION\.md).{0,24}(再開|続行|進め|resume|continue)'
    )
    if ((Test-ExplicitSelection $prompt $existing) -or $documentSelectionApplies) {
        $source = if ($null -ne $documentSelection) { $documentSelection.Source } else { 'conversation' }
        $state = [ordered]@{ schemaVersion = 1; sessionId = $sessionId; cwd = $cwd; status = 'selected'; selectionSource = $source; reasons = @(); updatedAt = [DateTime]::UtcNow.ToString('o') }
        $null = Write-State $state
        exit 0
    }

    $classification = Get-WorkflowClassification $prompt
    if ($classification.Required -and ($null -eq $existing -or $existing.status -ne 'selected')) {
        $state = [ordered]@{ schemaVersion = 1; sessionId = $sessionId; cwd = $cwd; status = 'pending'; recommendationPresented = $false; reasons = $classification.Reasons; updatedAt = [DateTime]::UtcNow.ToString('o') }
        $null = Write-State $state
        $reasonText = [string]::Join('、', $classification.Reasons)
        Write-JsonResult @{
            hookSpecificOutput = @{
                hookEventName = 'UserPromptSubmit'
                additionalContext = "AIRules workflow gate: この作業は担当AI・モデル・思考深度の選択待ち（判定: $reasonText）。読取調査は可能だが、設計確定・変更・委譲の前に推奨案と品質・費用・時間差を提示して回答を待つこと。"
            }
        }
    }
    exit 0
}

if ($eventName -eq 'PreToolUse') {
    $state = Get-EffectiveState $payload
    if ($null -eq $state -or $state.status -ne 'pending') { exit 0 }
    $toolName = [string](Get-PropertyValue $payload 'tool_name')
    $toolInput = Get-PropertyValue $payload 'tool_input'
    if (-not (Test-MutatingTool $toolName $toolInput)) { exit 0 }

    $reasonText = [string]::Join('、', @($state.reasons))
    Write-JsonResult @{
        hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = "AIRules workflow gate: 担当AI・モデル・思考深度が未選択のため $toolName を停止した（$reasonText）。推奨案と品質・費用・時間差を提示し、ユーザー回答後に再実行すること。"
        }
        systemMessage = 'AIRules: workflow selection is pending; mutating/delegating tool call denied.'
    }
}

if ($eventName -eq 'Stop') {
    $state = Get-EffectiveState $payload
    if ($null -eq $state -or $state.status -ne 'pending') { Write-JsonResult @{} }
    $message = [string](Get-PropertyValue $payload 'last_assistant_message')
    if (Test-CompliantRecommendation $message) {
        $state.recommendationPresented = $true
        $state.updatedAt = [DateTime]::UtcNow.ToString('o')
        $null = Write-State $state
        Write-JsonResult @{}
    }
    Write-JsonResult @{
        decision = 'block'
        reason = 'AIRules workflow gate: 担当AI・モデル・思考深度の推奨案と品質・費用・時間差を提示し、ユーザーの選択を待つ応答へ直すこと。設計・実装内容を先に確定してはならない。'
    }
}

exit 0
