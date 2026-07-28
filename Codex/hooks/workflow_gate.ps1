# AIRULES-MANAGED-HOOK schema=1 source=Codex/hooks/workflow_gate.ps1
# Shared PreToolUse/UserPromptSubmit/Stop gate for Claude Code and Codex.
# The gate records only classification state; prompts and transcripts are not copied.
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$script:StateSchemaVersion = 3

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
        if ($state.schemaVersion -ne $script:StateSchemaVersion -or $state.sessionId -ne $SessionId) { return $null }
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

function Test-NaturalApprovalText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt 160) { return $false }
    $answer = $Text.Trim()
    if ($answer -match '(?i)(いいえ|違う|変更して|選び直|やめ|中止|not\s+that|no\b)') { return $false }
    return $answer -match '(?i)^([1-3１-３]|推奨|おすすめ|はい|うん|了解|了承|承認|よい|良い|それで|その案で|推奨案で|おすすめで|そのまま|進めて|続けて|お願いします|任せます?|ok|okay|yes|proceed)(番|案|で)?(進めて(ください)?|お願いします|構いません|でよいです|で良いです)?[。.!！]?$'
}

function Test-ExplicitSelection {
    param([string]$Text, [hashtable]$ExistingState)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    if ($Text -match '(?im)^\s*AIRULES_WORKFLOW_SELECTION:\s*owner=(Codex|Claude|current);\s*model=([A-Za-z0-9._-]+);\s*thinking=(low|medium|high|xhigh|max|ultra);\s*scope=.+$') {
        return $true
    }
    if ($Text -match '(?i)(現在|今|起動中|選択中).{0,20}(AI|Codex|Claude|モデル|設定).{0,40}(そのまま|続行|進め|使って|任せ)') {
        return $true
    }

    $hasOwner = $Text -match '(?i)(担当\s*(AI)?\s*[:：=]?\s*(Codex|Claude)|owner\s*[:=]\s*(Codex|Claude)|現在のAI|current\s+(AI|agent))'
    $hasModel = $Text -match '(?i)(モデル\s*[:：=]\s*\S+|model\s*[:=]\s*[A-Za-z0-9._-]+|\b(opus|sonnet|haiku|fable|gpt-[A-Za-z0-9._-]+)\b)'
    $hasThinking = $Text -match '(?i)(思考深度\s*[:：=]?\s*(低|中|高|low|medium|high|xhigh|max|ultra)|reasoning(_effort)?\s*[:=]\s*(low|medium|high|xhigh|max|ultra)|effort\s*[:=]\s*(low|medium|high|xhigh|max|ultra))'
    if ($hasOwner -and $hasModel -and $hasThinking) { return $true }

    if ($null -ne $ExistingState -and $ExistingState.status -eq 'pending' -and
        $ExistingState.recommendationPresented -eq $true -and $Text.Length -le 160) {
        return Test-NaturalApprovalText $Text
    }
    return $false
}

function Test-NegatedTerm {
    param([string]$Text, [string]$Term)
    $escaped = [regex]::Escape($Term)
    return ($Text -match "(?i)$escaped.{0,18}(変更しない|変えない|触らない|対象外|維持|禁止)") -or
        ($Text -match "(?i)(without\s+changing|do\s+not\s+(change|touch)|keep).{0,24}$escaped")
}

function Get-WorkflowRequestText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    # Codex may include repository instructions and environment metadata in the user
    # payload. They describe policy/context, not the action requested by the user.
    $request = [regex]::Replace($Text, '(?is)<INSTRUCTIONS>.*?</INSTRUCTIONS>', ' ')
    $request = [regex]::Replace($request, '(?is)<environment_context>.*?</environment_context>', ' ')
    $request = [regex]::Replace($request, '(?im)^\s*#\s*AGENTS\.md instructions\s*$', ' ')
    return $request.Trim()
}

function Test-DocumentationOnlyChange {
    param([string]$Text)
    $filePattern = '(?i)(?<![A-Za-z0-9_.-])[A-Za-z0-9_.-]+\.(?<ext>[A-Za-z0-9]+)(?![A-Za-z0-9_.-])'
    $files = @([regex]::Matches($Text, $filePattern))
    if ($files.Count -gt 0) {
        $nonDocument = @($files | Where-Object { $_.Groups['ext'].Value -notmatch '^(md|txt|rst|adoc)$' })
        return $nonDocument.Count -eq 0
    }
    return $Text -match '(?i)(README|CHANGELOG|文書|ドキュメント|説明書|手順書).{0,20}(修正|変更|更新|編集|追加|削減|整理)'
}

function Test-ExplicitMinorImplementation {
    param(
        [string]$Text,
        [bool]$Design,
        [bool]$Review,
        [bool]$Delegation
    )
    if ($Design -or $Delegation) { return $false }

    $targetPattern = '(?i)(?<![A-Za-z0-9_.-])[A-Za-z0-9_.-]+\.(cs|cpp|cc|c|h|hpp|gd|ts|tsx|js|jsx|py|java|kt|rs|go|rb|php|swift|md|txt|json|ya?ml|toml|ps1|sh)(?![A-Za-z0-9_.-])'
    $targets = @([regex]::Matches($Text, $targetPattern) | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
    if ($targets.Count -lt 1 -or $targets.Count -gt 2) { return $false }
    if ($targets.Count -eq 2 -and @($targets | Where-Object { $_ -match '(?i)(test|tests|spec|specs)' }).Count -ne 1) { return $false }

    $localChange = $Text -match '(?i)(誤字|typo|文言|コメント|comment|import|using|定数値?|constant|比較演算子|条件式|Nullチェック|null\s*(check|guard))'
    $singleLocation = $Text -match '(?i)(1箇所|一箇所|1か所|一か所|単一|だけ|のみ|指定された|明示された|既存メソッド内|existing\s+method)'
    if (-not ($localChange -and $singleLocation)) { return $false }

    $disallowed = $Text -match '(?i)(Public\s+API|公開API|データ構造|保存形式|schema|スキーマ|データ移行|外部依存|外部ライブラリ|dependency|package追加|SDK追加|設定|config|Project\s+Settings|Build\s+Settings|Tags\s+and\s+Layers|project\.godot|security|セキュリティ|認証|権限|責務分割|依存方向|状態遷移|公開境界|新規.{0,8}(ファイル|クラス|型|interface|メソッド|メンバー)|(ファイル|クラス|型|interface|メソッド|メンバー).{0,8}(追加|作成)|改名|リネーム|移動|削除|rename|delete|remove|複数ファイル|全体|一括|横断|呼び出し側)'
    return -not $disallowed
}

function Get-WorkflowClassification {
    param([string]$Text)
    $result = [ordered]@{ Required = $false; Reasons = @(); ResponsibilityCount = 0 }
    $Text = Get-WorkflowRequestText $Text
    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }

    $implementationMention = $Text -match '(?i)(実装|修正|変更|追加|削除|移行|更新|作成|構築|導入|置換|リファクタ|コーディング|コードを書|編集|直して|fix|implement|change|add|remove|migrate|update|create|build|refactor|write\s+code|edit)'
    $design = $Text -match '(?i)(設計|アーキテクチャ|責務分割|依存方向|状態遷移|公開境界|design|architecture)'
    $review = $Text -match '(?i)(レビュー|査読|review|検証して|検証してください|(差分|実装結果|コード).{0,12}(確認して|確認してください|検証して|検証してください))'
    $delegation = $Text -match '(?i)(Sub\s*Agent|サブエージェント|複数AI|別AI|委譲|並列作業|並列実装|相互レビュー|multi-agent|delegate)'
    $positiveImplementation = $Text -match '(?i)((実装|修正|変更|追加|削除|移行|更新|作成|構築|導入|置換|リファクタ|コーディング|編集)\s*(を\s*)?(して|してください|してほしい|お願い|進めて|行って|実施して|対応して|任せて|着手して)|コードを書(いて|く|き)|直して|作って|fix\s+(it|this|the)|implement\s+(it|this|the)|please\s+(implement|change|add|remove|edit))'
    $negatedImplementation = $Text -match '(?i)((実装|修正|変更|追加|削除|更新|作成|コーディング|編集|コードを書).{0,12}(ではない|じゃない|しない|不要|伴わない|行わない|対象外|禁止)|(コード|ファイル).{0,12}(変更しない|編集しない|触らない)|without\s+(coding|implementation|changes)|do\s+not\s+(implement|change|edit|modify))'
    $readOnlyRequest = $Text -match '(?i)(調査|質問|回答|説明|解説|相談|対話|教えて|確認して|確認してください|分析|原因特定|できますか|できる[？?]|可能ですか|[？?]|investigate|explain|answer|question|consult|discuss|analy[sz]e|is it possible|can (you|we|i))'
    $terseImplementation = $implementationMention -and $Text -match '(?i)^\s*.{0,100}(実装|修正|変更|追加|削除|移行|更新|作成|構築|導入|置換|リファクタ|fix|implement|change|add|remove|migrate|update|create|build|refactor)\s*[。.!！]?\s*$'
    $implementation = $positiveImplementation -or ($terseImplementation -and -not $readOnlyRequest -and -not $negatedImplementation)
    if (-not $implementation) { return $result }

    if ($readOnlyRequest -and -not $positiveImplementation) { return $result }
    if (Test-DocumentationOnlyChange $Text) { return $result }
    if ($implementation -and (Test-ExplicitMinorImplementation $Text $design $review $delegation)) { return $result }

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
            if (($implementation -or $design) -and $Text -match [regex]::Escape($term) -and -not (Test-NegatedTerm $Text $term)) {
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

    if ($design) { $reasons.Add('設計') }
    if ($implementation) { $reasons.Add('実装・修正') }
    if ($review) { $reasons.Add('レビュー') }
    if (($implementation -or $design) -and $categoryCount -ge 2) { $reasons.Add('複数責務変更') }
    if ($delegation) {
        $reasons.Add('担当・モデル選択で品質・費用・時間が変わる分担')
    }

    $uniqueReasons = @($reasons | Select-Object -Unique)
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
            $state = [ordered]@{ schemaVersion = $script:StateSchemaVersion; sessionId = $sessionId; cwd = $cwd; status = 'selected'; enforceCurrent = $false; reasons = @(); updatedAt = [DateTime]::UtcNow.ToString('o') }
            continue
        }
        $classification = Get-WorkflowClassification $prompt
        if ($classification.Required -and ($null -eq $state -or $state.status -ne 'selected')) {
            $state = [ordered]@{ schemaVersion = $script:StateSchemaVersion; sessionId = $sessionId; cwd = $cwd; status = 'pending'; enforceCurrent = $true; recommendationPresented = $false; reasons = $classification.Reasons; updatedAt = [DateTime]::UtcNow.ToString('o') }
        } elseif ($null -ne $state -and $state.status -eq 'pending') {
            $state.enforceCurrent = $false
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
    if ($ToolName -match '(?i)^mcp__(node_repl|.*node.*)__js$') {
        $code = if ($ToolInput -is [string]) { $ToolInput } else { [string](Get-PropertyValue $ToolInput 'code') }
        if ([string]::IsNullOrWhiteSpace($code)) { $code = [string](Get-PropertyValue $ToolInput 'script') }
        if ([string]::IsNullOrWhiteSpace($code)) { $code = [string](Get-PropertyValue $ToolInput 'input') }
        if ([string]::IsNullOrWhiteSpace($code)) { return $true }
        if ($code -match '(?i)(writeFile|appendFile|truncate|unlink|rmSync|rename|mkdir|rmdir|copyFile|createWriteStream|apply_patch|shell_command|exec_command|child_process|spawn\(|exec\(|\bPOST\b|\bPUT\b|\bPATCH\b|\bDELETE\b|click\(|fill\(|type\(|press\(|upload|download|install|create_|update_|delete_|remove_|move_|rename_|write_|execute_)') { return $true }
        foreach ($call in [regex]::Matches($code, '(?i)tools\.([A-Za-z0-9_]+)')) {
            $tool = $call.Groups[1].Value
            if ($tool -notmatch '(?i)(^|__)(get|list|read|search|find|query|fetch|view|inspect|open)[A-Za-z0-9_]*$') { return $true }
        }
        return $false
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
    $hasWorkerPlan = $Message -match '(?i)(Worker|Sub\s*Agent|サブエージェント)'
    $hasCurrentSetting = $Message -match '(?i)(現在|現行|current).{0,50}(モデル|model|gpt-|opus|sonnet|haiku).{0,50}(思考深度|reasoning|effort|low|medium|high|xhigh|max|ultra)'
    $tradeoffCount = 0
    foreach ($pattern in @('品質|quality', '費用|cost|token', '時間|所要|速度|time|latency')) {
        if ($Message -match "(?i)$pattern") { $tradeoffCount++ }
    }
    $hasFirstOption = $Message -match '(?im)^\s*(?:[-*]\s*)?(?:1|１)[.)、：:\s]'
    $hasSecondOption = $Message -match '(?im)^\s*(?:[-*]\s*)?(?:2|２)[.)、：:\s]'
    $recommendedFirst = $Message -match '(?im)^\s*(?:[-*]\s*)?(?:1|１)[.)、：:\s].{0,80}(推奨|おすすめ|recommended)'
    $hasShortReply = $Message -match '(?i)(推奨|おすすめ).{0,24}(1|１)|(?:1|１).{0,24}(推奨|おすすめ)|[「『`]?1[」』`]?(\s*(または|/|・|、)\s*[「『`]?[2-3][」』`]?)?.{0,30}(回答|返信|選択|送)'
    $waitsForUser = $Message -match '(?i)(回答|選択|指定|どれ|よいですか|待ちます|確認|choose|reply|which)'
    return $hasOwner -and $hasModel -and $hasThinking -and $hasWorkerPlan -and $hasCurrentSetting -and
        $tradeoffCount -ge 2 -and $hasFirstOption -and $hasSecondOption -and $recommendedFirst -and
        $hasShortReply -and $waitsForUser
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
        $existing = [ordered]@{ schemaVersion = $script:StateSchemaVersion; sessionId = $sessionId; cwd = $cwd; status = 'none'; enforceCurrent = $false; reasons = @(); updatedAt = [DateTime]::UtcNow.ToString('o') }
        $null = Write-State $existing
    }

    $documentSelection = Get-DocumentSelection $cwd
    $documentSelectionApplies = $null -ne $documentSelection -and (
        $prompt.IndexOf([string]$documentSelection.Scope, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $prompt -match '(?i)(PLAN\.md|SESSION\.md).{0,24}(再開|続行|進め|resume|continue)'
    )
    if ((Test-ExplicitSelection $prompt $existing) -or $documentSelectionApplies) {
        $source = if ($null -ne $documentSelection) { $documentSelection.Source } else { 'conversation' }
        $state = [ordered]@{ schemaVersion = $script:StateSchemaVersion; sessionId = $sessionId; cwd = $cwd; status = 'selected'; enforceCurrent = $false; selectionSource = $source; reasons = @(); updatedAt = [DateTime]::UtcNow.ToString('o') }
        $null = Write-State $state
        exit 0
    }

    $classification = Get-WorkflowClassification $prompt
    if ($classification.Required -and ($null -eq $existing -or $existing.status -ne 'selected')) {
        $state = [ordered]@{ schemaVersion = $script:StateSchemaVersion; sessionId = $sessionId; cwd = $cwd; status = 'pending'; enforceCurrent = $true; recommendationPresented = $false; reasons = $classification.Reasons; updatedAt = [DateTime]::UtcNow.ToString('o') }
        $null = Write-State $state
        $reasonText = [string]::Join('、', $classification.Reasons)
        Write-JsonResult @{
            hookSpecificOutput = @{
                hookEventName = 'UserPromptSubmit'
                additionalContext = "AIRules workflow gate: この作業は担当AI・モデル・思考深度の選択待ち（判定: $reasonText）。読取調査は可能だが、実変更前に現在設定を示し、推奨を1番にした2〜3個の番号付き候補として、各候補の担当・モデル・思考深度・Worker使用有無と品質・費用・時間差を提示すること。ユーザーは「推奨」または番号だけで回答できるようにする。親Codexと選択モデルまたは思考深度が異なる場合は、指定値のWorkerを必ず起動して実装を任せ、親が切り替わったとは扱わないこと。"
            }
        }
    }
    if ($null -ne $existing -and $existing.status -eq 'pending') {
        $existing.enforceCurrent = Test-NaturalApprovalText $prompt
        $existing.updatedAt = [DateTime]::UtcNow.ToString('o')
        $null = Write-State $existing
    }
    exit 0
}

if ($eventName -eq 'PreToolUse') {
    $state = Get-EffectiveState $payload
    if ($null -eq $state -or $state.status -ne 'pending' -or $state.enforceCurrent -ne $true) { exit 0 }
    $toolName = [string](Get-PropertyValue $payload 'tool_name')
    $toolInput = Get-PropertyValue $payload 'tool_input'
    if (-not (Test-MutatingTool $toolName $toolInput)) { exit 0 }

    $reasonText = [string]::Join('、', @($state.reasons))
    Write-JsonResult @{
        hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = "AIRules workflow gate: 担当AI・モデル・思考深度が未選択のため $toolName を停止した（$reasonText）。現在設定を示し、推奨を1番にした2〜3個の番号付き候補として担当・モデル・思考深度・Worker使用有無と品質・費用・時間差を提示すること。ユーザーは「推奨」または番号だけで回答できる。親Codexと異なるモデルまたは思考深度の選択時は、指定値のWorker起動が必須。"
        }
        systemMessage = 'AIRules: workflow selection is pending; mutating/delegating tool call denied.'
    }
}

if ($eventName -eq 'Stop') {
    $state = Get-EffectiveState $payload
    if ($null -eq $state -or $state.status -ne 'pending' -or $state.enforceCurrent -ne $true) { Write-JsonResult @{} }
    $message = [string](Get-PropertyValue $payload 'last_assistant_message')
    if (Test-CompliantRecommendation $message) {
        $state.recommendationPresented = $true
        $state.updatedAt = [DateTime]::UtcNow.ToString('o')
        $null = Write-State $state
        Write-JsonResult @{}
    }
    Write-JsonResult @{
        decision = 'block'
        reason = 'AIRules workflow gate: 現在設定を示し、推奨を1番にした2〜3個の番号付き候補として、各候補の担当AI・モデル・思考深度・Worker/Sub Agentの使用有無と品質・費用・時間差を提示すること。「推奨」または番号だけで回答できると明記し、ユーザーの選択を待つ応答へ直すこと。親Codexと異なるモデルまたは思考深度の選択時は指定値のWorker起動が必須。実変更を先に進めてはならない。'
    }
}

exit 0
