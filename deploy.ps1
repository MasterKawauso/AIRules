# AIRules deployment script.  The repository is the source of truth.
[CmdletBinding()]
param(
    # Test-only override; normal invocation always deploys to the current user's home directory.
    [string]$HomeDirectory = $HOME,
    # Test-only override keeps temporary-environment backups outside the repository.
    [string]$BackupDirectory = (Join-Path $PSScriptRoot 'backup')
)

$ErrorActionPreference = 'Stop'

$repo = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$backupRoot = Join-Path $BackupDirectory $stamp
$codexHome = Join-Path $HomeDirectory '.codex'
$claudeHome = Join-Path $HomeDirectory '.claude'
$manifestPath = Join-Path $claudeHome 'airules-deployment-manifest.json'
$header = "<!-- AUTO-GENERATED from $repo : 直接編集せず、リポジトリを編集して deploy.ps1 を再実行すること -->"
$utf8 = [System.Text.UTF8Encoding]::new($false)
$warnings = [System.Collections.Generic.List[string]]::new()
$backupCount = 0

function Add-WarningMessage {
    param([string]$Message)
    $script:warnings.Add($Message)
    Write-Warning $Message
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-ManagedHookTarget {
    param(
        [string]$Source,
        [string]$Live,
        [string[]]$LegacyHashes = @()
    )
    $sourceReader = [IO.File]::OpenText($Source)
    try { $sourceFirstLine = $sourceReader.ReadLine() } finally { $sourceReader.Dispose() }
    if ($sourceFirstLine -cnotmatch '^# AIRULES-MANAGED-HOOK schema=1 source=(Codex|Claude)/hooks/[^/\\]+\.ps1$') {
        throw "Managed hook source has no valid marker: $Source"
    }
    if (-not (Test-Path -LiteralPath $Live)) { return }
    if (-not (Test-Path -LiteralPath $Live -PathType Leaf)) { throw "Hook target exists but is not a file: $Live" }

    $liveReader = [IO.File]::OpenText($Live)
    try { $liveFirstLine = $liveReader.ReadLine() } finally { $liveReader.Dispose() }
    $marked = $liveFirstLine -cmatch '^# AIRULES-MANAGED-HOOK schema=1 source=(Codex|Claude)/hooks/[^/\\]+\.ps1$'
    $legacy = $LegacyHashes -contains (Get-Sha256 $Live)
    if (-not $marked -and -not $legacy) {
        throw "Refusing to overwrite non-AIRules hook file: $Live"
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Backup-Item {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Ensure-Directory $backupRoot
    $destination = Join-Path $backupRoot $Label
    if (Test-Path -LiteralPath $destination) { throw "Backup destination already exists: $destination" }
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
    $script:backupCount++
}

function Write-Bytes {
    param([string]$Path, [byte[]]$Bytes)
    Ensure-Directory (Split-Path -Parent $Path)
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

function Write-HeaderWrappedCopy {
    param([string]$Source, [string]$Destination)
    $prefix = $utf8.GetBytes($header + "`r`n`r`n")
    $body = [System.IO.File]::ReadAllBytes($Source)
    $bytes = [byte[]]::new($prefix.Length + $body.Length)
    [Array]::Copy($prefix, 0, $bytes, 0, $prefix.Length)
    [Array]::Copy($body, 0, $bytes, $prefix.Length, $body.Length)
    Write-Bytes $Destination $bytes
}

function ConvertTo-YamlString {
    param([string]$Value)
    # A JSON string is a valid YAML double-quoted scalar and safely encodes quotes/newlines/colons.
    return ($Value | ConvertTo-Json -Compress)
}

function Get-ManagedHookDefinitions {
    param(
        [string]$DefinitionPath,
        [string]$HomeToken,
        [string]$HomePath
    )
    $definitions = Get-Content -Raw -LiteralPath $DefinitionPath | ConvertFrom-Json -AsHashtable
    $managed = [ordered]@{}
    foreach ($eventName in @('PreToolUse', 'UserPromptSubmit', 'Stop')) {
        if (-not $definitions.Contains($eventName)) { throw "Hook definition is missing '$eventName': $DefinitionPath" }
        $managed[$eventName] = @()
        foreach ($definition in @($definitions[$eventName])) {
            if ($definition -isnot [System.Collections.IDictionary] -or -not $definition.Contains('command')) { throw "Hook definition for '$eventName' is invalid: $DefinitionPath" }
            $entry = [ordered]@{
                command = ([string]$definition.command).Replace($HomeToken, $HomePath)
            }
            if ([string]::IsNullOrWhiteSpace($entry.command)) { throw "Hook definition for '$eventName' has an empty command: $DefinitionPath" }
            if ($definition.Contains('matcher')) { $entry.matcher = [string]$definition.matcher }
            $managed[$eventName] += $entry
        }
    }
    if ($definitions.Keys.Count -ne $managed.Keys.Count) { throw "Hook definition contains unsupported entries: $DefinitionPath" }
    return $managed
}

function Install-StagedFile {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Live,
        [int]$Attempts = 10
    )
    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Live) { Remove-Item -LiteralPath $Live -Force }
            Move-Item -LiteralPath $Stage -Destination $Live
            return
        } catch {
            $lastError = $_
            if ($attempt -lt $Attempts) { Start-Sleep -Milliseconds 100 }
        }
    }
    throw $lastError
}

function Merge-ManagedHooks {
    param([hashtable]$Hooks, [hashtable]$ManagedHooks)
    foreach ($eventName in $ManagedHooks.Keys) {
        $managedDefinitions = @($ManagedHooks[$eventName])
        $managedCommands = @($managedDefinitions | ForEach-Object { $_.command })
        $existingEntries = if ($Hooks.Contains($eventName)) { @($Hooks[$eventName]) } else { @() }
        $remainingEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $existingEntries) {
            if ($entry -isnot [System.Collections.IDictionary] -or -not $entry.Contains('hooks')) {
                $remainingEntries.Add($entry)
                continue
            }
            $remainingCommands = [System.Collections.Generic.List[object]]::new()
            foreach ($hook in @($entry.hooks)) {
                if ($hook -is [System.Collections.IDictionary] -and $hook.Contains('command') -and $managedCommands -contains $hook.command) { continue }
                $remainingCommands.Add($hook)
            }
            if ($remainingCommands.Count -gt 0) {
                $entry.hooks = @($remainingCommands)
                $remainingEntries.Add($entry)
            }
        }
        foreach ($managed in $managedDefinitions) {
            $entry = [ordered]@{}
            if ($managed.Contains('matcher')) { $entry.matcher = $managed.matcher }
            $entry.hooks = @([ordered]@{ type = 'command'; command = $managed.command })
            $remainingEntries.Add($entry)
        }
        $Hooks[$eventName] = @($remainingEntries)
    }
    return $Hooks
}

# Claude配備物では ~/.claude/airules/ が存在しないため、本文中のルール相互参照
# (`REQUIREMENTS.md` など) を対応するSkill参照へ機械変換する。リポジトリ側の正本は
# 無改変のまま。完全一致トークンのみを対象とし、正規表現の広域置換は行わない。
function ConvertTo-ClaudeSkillBody {
    param([byte[]]$SourceBytes, [hashtable]$SkillsByFile, [string]$SourceName)
    $text = $utf8.GetString($SourceBytes)
    foreach ($entry in $SkillsByFile.GetEnumerator()) {
        # 元本文はルール名をバッククォートで囲んで参照している。その形だけを置換する。
        $token = '`' + $entry.Key + '`'
        $count = ([regex]::Matches($text, [regex]::Escape($token))).Count
        if ($count -eq 0) { continue }
        # 置換は読み込み導線の付け替えのみを意図している。同一文書内で同じルール名が
        # 多数出る場合は、説明文中の言及を巻き込んでいる可能性があるため可視化する。
        if ($count -gt 2) {
            Add-WarningMessage "${SourceName}: '$($entry.Key)' を $count 箇所でSkill参照へ変換した。説明文中の言及を巻き込んでいないか確認すること。"
        }
        $text = $text.Replace($token, '`/' + $entry.Value + '`')
    }
    return $utf8.GetBytes($text)
}

function Test-GeneratedSkill {
    param([string]$SkillPath, [string]$SourcePath, [string]$Name, [string]$Description, [byte[]]$ExpectedBody)
    $bytes = [System.IO.File]::ReadAllBytes($SkillPath)
    $sourceBytes = $ExpectedBody
    $marker = "<!-- AIRULES-MANAGED schema=1 source=Codex/airules/$([IO.Path]::GetFileName($SourcePath)) -->`r`n"
    $frontmatter = "---`r`nname: $(ConvertTo-YamlString $Name)`r`ndescription: $(ConvertTo-YamlString $Description)`r`n---`r`n"
    $prefix = $utf8.GetBytes($frontmatter + $marker)
    if ($bytes.Length -lt $prefix.Length) { throw "SKILL.md is shorter than its generated prefix: $SkillPath" }
    for ($i = 0; $i -lt $prefix.Length; $i++) {
        if ($bytes[$i] -ne $prefix[$i]) { throw "Invalid YAML frontmatter or management marker: $SkillPath" }
    }
    # Validate the two generated scalar values by parsing their JSON/YAML-compatible representation.
    $null = (ConvertTo-YamlString $Name | ConvertFrom-Json)
    $null = (ConvertTo-YamlString $Description | ConvertFrom-Json)
    $body = [byte[]]::new($bytes.Length - $prefix.Length)
    [Array]::Copy($bytes, $prefix.Length, $body, 0, $body.Length)
    $actualHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($body)).Replace('-', '')
    $expectedHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($sourceBytes)).Replace('-', '')
    if ($actualHash -ne $expectedHash) { throw "Generated SKILL.md body hash differs from source: $SkillPath" }
}

function Test-ManagedSkillDirectory {
    param([string]$Directory, [hashtable]$PreviousSkillNames)
    $name = [IO.Path]::GetFileName($Directory)
    $registered = $PreviousSkillNames.ContainsKey($name)
    $skillFile = Join-Path $Directory 'SKILL.md'
    $marked = $false
    if (Test-Path -LiteralPath $skillFile -PathType Leaf) {
        # マーカーは生成時に必ずfrontmatter終端 '---' の直後の行へ置かれる。
        # 本文のどこかに同じ文字列があるだけで管理対象と見なすと、マーカー例を
        # 記載しただけのユーザー製Skillまで上書き対象になるため、位置と書式を検証する。
        $skillLines = @([System.IO.File]::ReadAllLines($skillFile))
        if ($skillLines.Count -ge 4 -and $skillLines[0] -eq '---') {
            for ($i = 1; $i -lt $skillLines.Count; $i++) {
                if ($skillLines[$i] -eq '---') {
                    if ($i + 1 -lt $skillLines.Count) {
                        # -match は既定で大文字小文字を区別しないため、生成物と完全一致する
                        # マーカーだけを認めるよう -cmatch を使う。
                        $marked = $skillLines[$i + 1] -cmatch '^<!-- AIRULES-MANAGED schema=1 source=Codex/airules/[^/\\]+\.md -->$'
                    }
                    break
                }
            }
        }
    }
    return @{ Registered = $registered; Marked = $marked; Managed = ($registered -and $marked) }
}

function Assert-ExpectedClaudeAgentsTransform {
    param([string]$SourcePath, [hashtable]$SkillsByFile)
    $text = [System.IO.File]::ReadAllText($SourcePath)
    $leadIn = 'Codex/Claude Code共通の常時ルール。条件付きルールは`airules/`にあり、必要な文書だけをセッション中1回読む（内容が既に文脈にあれば再読不要）。'
    $newLeadIn = 'Codex/Claude Code共通の常時ルール。条件付きルールは対応するSkillsとして提供され、必要な文書だけをセッション中1回読む（内容が既に文脈にあれば再読不要）。'
    $replacements = [ordered]@{
        'REQUIREMENTS.md' = '/airules-requirements'
        'PITFALLS.md、THINKING.md' = '/airules-pitfalls、/airules-thinking'
        'THINKING.md、DESIGN.md' = '/airules-thinking、/airules-design'
        'WORKFLOW.md' = '/airules-workflow'
        'UNITY.md/UE5.md/GODOT.md' = '/airules-unity・/airules-ue5・/airules-godot'
        'GAME_COMMON.md' = '/airules-game-common'
        'REVIEW.md' = '/airules-review'
        'GIT.md' = '/airules-git'
        'GITHUB.md' = '/airules-github'
    }
    foreach ($file in @('REQUIREMENTS.md','PITFALLS.md','THINKING.md','DESIGN.md','WORKFLOW.md','UNITY.md','UE5.md','GODOT.md','GAME_COMMON.md','REVIEW.md','GIT.md','GITHUB.md')) {
        if (-not $SkillsByFile.ContainsKey($file)) { throw "Claude AGENTS.md references missing source rule: $file" }
    }
    $leadCount = [regex]::Matches($text, [regex]::Escape($leadIn)).Count
    if ($leadCount -ne 1) { throw "Claude AGENTS.md lead-in expected once, found $leadCount. No files were written." }
    foreach ($entry in $replacements.GetEnumerator()) {
        # These are exact table-cell tokens, not document-wide substitutions.
        $count = ([regex]::Matches($text, [regex]::Escape("| $($entry.Key) |"))).Count
        if ($count -ne 1) { throw "Claude AGENTS.md token '$($entry.Key)' expected once in the table, found $count. No files were written." }
    }
    $lines = $text -split "`r?`n", 0
    $inTable = $false
    $tableHeadingSeen = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq $leadIn) { $lines[$i] = $newLeadIn; continue }
        foreach ($entry in $replacements.GetEnumerator()) {
            $oldCell = "| $($entry.Key) |"
            if ($lines[$i].Contains($oldCell)) { $lines[$i] = $lines[$i].Replace($oldCell, "| $($entry.Value) |") }
        }
        # 条件付きルール表に未変換の .md 参照が残っていれば、表へ行が追加されたのに
        # 変換定義が更新されていない。Claude側には airules/ が無いため壊れた参照になる。
        if ($lines[$i].TrimEnd() -eq '## 条件付きルール（作業前に必読）') { $inTable = $true; $tableHeadingSeen = $true; continue }
        if ($inTable) {
            if ($lines[$i].StartsWith('## ')) { $inTable = $false; continue }
            if ($lines[$i].StartsWith('|') -and $lines[$i] -match '[A-Za-z0-9_]+\.md') {
                throw "Claude AGENTS.md table row still references a raw rule file after conversion: $($lines[$i]). Update the replacement map in deploy.ps1. No files were written."
            }
        }
    }
    # 見出しが改名されると上の検査が黙って無効になるため、見出しの存在自体を必須にする。
    if (-not $tableHeadingSeen) { throw "Claude AGENTS.md conditional-rule table heading was not found; the unconverted-reference check would be silently skipped. No files were written." }
    return [string]::Join("`r`n", $lines)
}

try {
    Write-Host "=== AIRules deploy ($stamp) ==="
    $sourceAgents = Join-Path $repo 'Codex\AGENTS.md'
    $claudeManagedHooks = Get-ManagedHookDefinitions (Join-Path $repo 'Claude\settings-hooks.json') '<claudeHome>' $claudeHome
    $codexManagedHooks = Get-ManagedHookDefinitions (Join-Path $repo 'Codex\settings-hooks.json') '<codexHome>' $codexHome
    $sharedHookSources = @(Get-ChildItem -LiteralPath (Join-Path $repo 'Codex\hooks') -Filter '*.ps1' -File)
    $claudeHookSources = @(Get-ChildItem -LiteralPath (Join-Path $repo 'Claude\hooks') -Filter '*.ps1' -File)
    $hookNameCollisions = @($sharedHookSources.Name | Where-Object { $claudeHookSources.Name -contains $_ })
    if ($hookNameCollisions.Count -gt 0) { throw "Shared/Claude hook source name collision: $($hookNameCollisions -join ', ')" }
    $legacyClaudeHookHashes = @{
        'read_progress.ps1' = @('20AAB59BD5295D152BFE82A93138C384521B4A220CC34F6C2EBD7311C8FDC6DA')
        'remind_progress.ps1' = @('C26B071DFB5165B6971636854332B4AE82D91B27023198773FCAEFDD54DABB10')
        'require_agent_model.ps1' = @('F3434426A993BA70FFC6377E2C528971439D25DD893DF4D4AC6E67E6FA6EE1DE')
    }
    foreach ($source in $claudeHookSources) {
        $legacy = if ($legacyClaudeHookHashes.ContainsKey($source.Name)) { $legacyClaudeHookHashes[$source.Name] } else { @() }
        Assert-ManagedHookTarget $source.FullName (Join-Path $claudeHome "hooks\$($source.Name)") $legacy
    }
    foreach ($source in $sharedHookSources) {
        Assert-ManagedHookTarget $source.FullName (Join-Path $claudeHome "hooks\$($source.Name)")
        Assert-ManagedHookTarget $source.FullName (Join-Path $codexHome "hooks\$($source.Name)")
    }
    $settingsPath = Join-Path $claudeHome 'settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        # 既存設定が壊れている場合は、ユーザー設定を失わないよう書き換えずに停止する。
        $claudeSettings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json -AsHashtable
    } else {
        $claudeSettings = [ordered]@{}
    }
    if (-not $claudeSettings.Contains('hooks')) { $claudeSettings.hooks = [ordered]@{} }
    if ($claudeSettings.hooks -isnot [System.Collections.IDictionary]) { throw 'Claude settings.json property hooks must be an object.' }
    $claudeSettings.hooks = Merge-ManagedHooks $claudeSettings.hooks $claudeManagedHooks

    $codexHooksPath = Join-Path $codexHome 'hooks.json'
    if (Test-Path -LiteralPath $codexHooksPath) {
        $codexHookDocument = Get-Content -Raw -LiteralPath $codexHooksPath | ConvertFrom-Json -AsHashtable
    } else {
        $codexHookDocument = [ordered]@{}
    }
    if (-not $codexHookDocument.Contains('hooks')) { $codexHookDocument.hooks = [ordered]@{} }
    if ($codexHookDocument.hooks -isnot [System.Collections.IDictionary]) { throw 'Codex hooks.json property hooks must be an object.' }
    $codexHookDocument.hooks = Merge-ManagedHooks $codexHookDocument.hooks $codexManagedHooks
    $sourceRules = @(Get-ChildItem -LiteralPath (Join-Path $repo 'Codex\airules') -Filter '*.md' -File | Sort-Object Name)
    if ($sourceRules.Count -eq 0) { throw 'No Codex/airules/*.md source files were found.' }
    $overrides = (Get-Content -Raw (Join-Path $repo 'Claude\skills\manifest.json') | ConvertFrom-Json).descriptionOverrides
    $skills = @()
    $skillsByFile = @{}
    foreach ($rule in $sourceRules) {
        $skillName = 'airules-' + (($rule.BaseName.ToLowerInvariant()) -replace '_', '-')
        # skill名は必ずディレクトリ名として使われる。'..' やセパレータを含む名前が
        # 混入すると、生成・削除がSkillsディレクトリの外へ届きうるため書式を固定する。
        if ($skillName -cnotmatch '^airules-[a-z0-9-]+$') { throw "Derived skill name is not a safe directory name: '$skillName' (from $($rule.Name))." }
        $sourceRelative = "Codex/airules/$($rule.Name)"
        $matches = @($overrides | Where-Object { $_.source -eq $sourceRelative })
        if ($matches.Count -gt 1) { throw "Multiple description overrides found for $sourceRelative" }
        if ($matches.Count -eq 1) { $description = [string]$matches[0].description }
        else {
            $paragraphLines = [System.Collections.Generic.List[string]]::new()
            $startedParagraph = $false
            foreach ($line in Get-Content -LiteralPath $rule.FullName) {
                if (-not $startedParagraph) {
                    if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
                    $startedParagraph = $true
                }
                if (-not $line.Trim()) { break }
                $paragraphLines.Add($line.Trim())
            }
            if ($paragraphLines.Count -gt 0) { $description = [string]::Join(' ', $paragraphLines) }
            else {
                $description = "$($rule.Name) のルールを適用する。"
                Add-WarningMessage "Description extraction failed for $($rule.Name); using generated fallback."
            }
        }
        $skills += [pscustomobject]@{ Name = $skillName; Source = $rule; Description = $description; RelativeSource = $sourceRelative }
        $skillsByFile[$rule.Name] = $skillName
    }
    $collisions = @($skills | Group-Object Name | Where-Object Count -gt 1)
    if ($collisions.Count -gt 0) { throw "Skill name collision: $($collisions.Name -join ', ')" }

    $claudeAgents = Assert-ExpectedClaudeAgentsTransform $sourceAgents $skillsByFile
    $previousSkillNames = @{}
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $previous = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
            # 配備記録の名前は孤児削除のパスへ渡る。'..' やセパレータを含む値を
            # 受け入れるとSkillsディレクトリ外を再帰削除しうるため、生成規則に合う
            # 名前だけを採用し、それ以外は無視して警告する。
            foreach ($name in @($previous.managedSkills)) {
                if ($null -eq $name) { continue }
                $candidateName = [string]$name
                if ($candidateName -cnotmatch '^airules-[a-z0-9-]+$') {
                    Add-WarningMessage "Ignoring unsafe skill name in previous deployment manifest: '$candidateName'"
                    continue
                }
                $previousSkillNames[$candidateName] = $true
            }
        } catch { Add-WarningMessage "Previous AIRules manifest is unreadable; no existing skill will be treated as managed. $_" }
    }

    # Preflight collisions and only inspect manifest-registered directories for possible skill orphans.
    $skillsHome = Join-Path $claudeHome 'skills'
    foreach ($skill in $skills) {
        $target = Join-Path $skillsHome $skill.Name
        if (Test-Path -LiteralPath $target) {
            $state = Test-ManagedSkillDirectory $target $previousSkillNames
            # 上書き可否はマーカーだけで判断する。マーカーはAIRulesが生成した証拠であり、
            # 配備記録は前回の実配備が完走したかどうかしか示さない。両方を要求すると、
            # Skill配置後・manifest確定前に失敗した場合に以後の配備が永久に拒否される。
            if (-not $state.Marked) { throw "Refusing to overwrite non-AIRules Claude skill '$target' (registered=$($state.Registered), marker=$($state.Marked))." }
            if (-not $state.Registered) { Add-WarningMessage "Adopting unregistered but AIRules-marked skill '$target' (前回の配備が中断した可能性がある)。" }
        }
    }
    $managedOrphans = @()
    foreach ($oldName in $previousSkillNames.Keys) {
        if ($skills.Name -contains $oldName) { continue }
        $candidate = Join-Path $skillsHome $oldName
        if (Test-Path -LiteralPath $candidate) {
            $state = Test-ManagedSkillDirectory $candidate $previousSkillNames
            if ($state.Managed) { $managedOrphans += $candidate }
            else { Add-WarningMessage "Leaving ambiguous Claude skill orphan '$candidate' (registered=$($state.Registered), marker=$($state.Marked))." }
        }
    }
    # 配備記録に無くマーカーだけを持つ孤児は上の走査に掛からない。前回が記録確定前に
    # 中断し、その後ルールを削除・改名した場合に無効なSkillが残り続けるため、
    # 削除はせず（記録が無い以上AIRules生成と断定しきれない）存在だけを知らせる。
    if (Test-Path -LiteralPath $skillsHome) {
        $knownNames = @($skills.Name) + @($previousSkillNames.Keys)
        Get-ChildItem -LiteralPath $skillsHome -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $knownNames -notcontains $_.Name } | ForEach-Object {
            if ((Test-ManagedSkillDirectory $_.FullName $previousSkillNames).Marked) {
                Add-WarningMessage "AIRulesマーカーを持つが配備記録に無いSkillが残っている: $($_.FullName)（不要なら手動で削除する）"
            }
        }
    }

    # All generated content is staged and verified before any live artifact is changed.
    Ensure-Directory $codexHome; Ensure-Directory $claudeHome
    $codexStage = Join-Path $codexHome ".airules-deploy-staging-$stamp"
    $claudeStage = Join-Path $claudeHome ".airules-deploy-staging-$stamp"
    Ensure-Directory $codexStage; Ensure-Directory $claudeStage
    Write-HeaderWrappedCopy $sourceAgents (Join-Path $codexStage 'AGENTS.md')
    foreach ($skill in $skills) { Write-HeaderWrappedCopy $skill.Source.FullName (Join-Path $codexStage "airules\$($skill.Source.Name)") }
    Get-ChildItem -LiteralPath (Join-Path $repo 'Codex\hooks') -File | ForEach-Object {
        Ensure-Directory (Join-Path $codexStage 'hooks')
        Ensure-Directory (Join-Path $claudeStage 'hooks')
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $codexStage "hooks\$($_.Name)") -Force
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $claudeStage "hooks\$($_.Name)") -Force
    }
    Write-Bytes (Join-Path $codexStage 'hooks.json') $utf8.GetBytes(($codexHookDocument | ConvertTo-Json -Depth 100))
    Write-Bytes (Join-Path $claudeStage 'AGENTS.md') $utf8.GetBytes($claudeAgents)
    Write-HeaderWrappedCopy (Join-Path $repo 'Claude\CLAUDE.md') (Join-Path $claudeStage 'CLAUDE.md')
    foreach ($folder in @('agents','output-styles','hooks')) {
        $sourceFolder = Join-Path $repo "Claude\$folder"
        if (Test-Path -LiteralPath $sourceFolder) {
            Get-ChildItem -LiteralPath $sourceFolder -File | ForEach-Object {
                Ensure-Directory (Join-Path $claudeStage $folder)
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $claudeStage "$folder\$($_.Name)") -Force
            }
        }
    }

    # Use Codex's own config writer against a staged CODEX_HOME. This changes only
    # features.hooks and validates the existing TOML before any live file is replaced.
    $codexConfigPath = Join-Path $codexHome 'config.toml'
    $codexConfigStageHome = Join-Path $codexStage 'config-home'
    Ensure-Directory $codexConfigStageHome
    if (Test-Path -LiteralPath $codexConfigPath) {
        Copy-Item -LiteralPath $codexConfigPath -Destination (Join-Path $codexConfigStageHome 'config.toml') -Force
    }
    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
    if ($null -eq $codexCommand) { throw 'Codex CLI is required to validate config.toml and enable the stable hooks feature.' }
    $previousCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = $codexConfigStageHome
        & $codexCommand.Source features enable hooks | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Codex rejected staged config.toml while enabling hooks (exit $LASTEXITCODE)." }
        & $codexCommand.Source features list | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Codex validation failed for staged config.toml (exit $LASTEXITCODE)." }
    } finally {
        $env:CODEX_HOME = $previousCodexHome
    }
    $stagedCodexConfig = Join-Path $codexConfigStageHome 'config.toml'
    if (-not (Test-Path -LiteralPath $stagedCodexConfig -PathType Leaf)) { throw 'Codex did not produce staged config.toml.' }
    foreach ($skill in $skills) {
        $destination = Join-Path $claudeStage "skills\$($skill.Name)\SKILL.md"
        $frontmatter = "---`r`nname: $(ConvertTo-YamlString $skill.Name)`r`ndescription: $(ConvertTo-YamlString $skill.Description)`r`n---`r`n"
        $marker = "<!-- AIRULES-MANAGED schema=1 source=$($skill.RelativeSource) -->`r`n"
        $prefix = $utf8.GetBytes($frontmatter + $marker)
        $sourceBytes = ConvertTo-ClaudeSkillBody ([System.IO.File]::ReadAllBytes($skill.Source.FullName)) $skillsByFile $skill.Source.Name
        $allBytes = [byte[]]::new($prefix.Length + $sourceBytes.Length)
        [Array]::Copy($prefix, 0, $allBytes, 0, $prefix.Length); [Array]::Copy($sourceBytes, 0, $allBytes, $prefix.Length, $sourceBytes.Length)
        Write-Bytes $destination $allBytes
        Test-GeneratedSkill $destination $skill.Source.FullName $skill.Name $skill.Description $sourceBytes
    }

    # Warn only for user-owned agent/style files; do not enumerate unrelated skills.
    foreach ($folder in @('agents','output-styles')) {
        $liveFolder = Join-Path $claudeHome $folder; $sourceFolder = Join-Path $repo "Claude\$folder"
        if (Test-Path -LiteralPath $liveFolder) {
            $sourceNames = @(Get-ChildItem -LiteralPath $sourceFolder -File | Select-Object -ExpandProperty Name)
            Get-ChildItem -LiteralPath $liveFolder -File | Where-Object { $sourceNames -notcontains $_.Name } | ForEach-Object { Add-WarningMessage "Leaving non-AIRules $folder file untouched: $($_.FullName)" }
        }
    }

    # Hook bodies go first. Configuration that references them is switched only
    # after every body and other artifact has been placed.
    Get-ChildItem -LiteralPath (Join-Path $claudeStage 'hooks') -File -ErrorAction SilentlyContinue | ForEach-Object {
        $live = Join-Path $claudeHome "hooks\$($_.Name)"; Backup-Item $live "claude-hooks-$($_.Name)"; Ensure-Directory (Split-Path -Parent $live)
        Install-StagedFile $_.FullName $live
    }
    Get-ChildItem -LiteralPath (Join-Path $codexStage 'hooks') -File -ErrorAction SilentlyContinue | ForEach-Object {
        $live = Join-Path $codexHome "hooks\$($_.Name)"; Backup-Item $live "codex-hooks-$($_.Name)"; Ensure-Directory (Split-Path -Parent $live)
        Install-StagedFile $_.FullName $live
    }

    # Backup first, then replace staged files/directories with same-volume moves.
    foreach ($pair in @(@{ Live = (Join-Path $codexHome 'AGENTS.md'); Stage = (Join-Path $codexStage 'AGENTS.md'); Label = 'codex-AGENTS.md' }, @{ Live = (Join-Path $claudeHome 'AGENTS.md'); Stage = (Join-Path $claudeStage 'AGENTS.md'); Label = 'claude-AGENTS.md' }, @{ Live = (Join-Path $claudeHome 'CLAUDE.md'); Stage = (Join-Path $claudeStage 'CLAUDE.md'); Label = 'claude-CLAUDE.md' })) {
        Backup-Item $pair.Live $pair.Label; if (Test-Path -LiteralPath $pair.Live) { Remove-Item -LiteralPath $pair.Live -Force }; Move-Item -LiteralPath $pair.Stage -Destination $pair.Live
    }
    $liveCodexRules = Join-Path $codexHome 'airules'
    if (Test-Path -LiteralPath $liveCodexRules) {
        Get-ChildItem -LiteralPath $liveCodexRules -File | Where-Object { $skills.Source.Name -notcontains $_.Name } | ForEach-Object { Backup-Item $_.FullName "codex-airules-orphan-$($_.Name)"; Remove-Item -LiteralPath $_.FullName -Force }
    }
    foreach ($skill in $skills) {
        $live = Join-Path $liveCodexRules $skill.Source.Name; Backup-Item $live "codex-airules-$($skill.Source.Name)"; Ensure-Directory $liveCodexRules
        if (Test-Path -LiteralPath $live) { Remove-Item -LiteralPath $live -Force }; Move-Item -LiteralPath (Join-Path $codexStage "airules\$($skill.Source.Name)") -Destination $live
    }
    foreach ($folder in @('agents','output-styles')) {
        Get-ChildItem -LiteralPath (Join-Path $claudeStage $folder) -File -ErrorAction SilentlyContinue | ForEach-Object {
            $live = Join-Path $claudeHome "$folder\$($_.Name)"; Backup-Item $live "claude-$folder-$($_.Name)"; Ensure-Directory (Split-Path -Parent $live)
            if (Test-Path -LiteralPath $live) { Remove-Item -LiteralPath $live -Force }; Move-Item -LiteralPath $_.FullName -Destination $live
        }
    }
    foreach ($skill in $skills) {
        $live = Join-Path $skillsHome $skill.Name; Backup-Item $live "claude-skill-$($skill.Name)"; Ensure-Directory $skillsHome
        if (Test-Path -LiteralPath $live) { Remove-Item -LiteralPath $live -Recurse -Force }; Move-Item -LiteralPath (Join-Path $claudeStage "skills\$($skill.Name)") -Destination $live
    }
    foreach ($orphan in $managedOrphans) { Backup-Item $orphan "claude-skill-orphan-$([IO.Path]::GetFileName($orphan))"; Remove-Item -LiteralPath $orphan -Recurse -Force }
    # Configuration is the final switch: at this point every referenced hook body exists.
    Backup-Item $settingsPath 'claude-settings.json'
    [System.IO.File]::WriteAllText($settingsPath, ($claudeSettings | ConvertTo-Json -Depth 100), $utf8)
    Backup-Item $codexHooksPath 'codex-hooks.json'
    if (Test-Path -LiteralPath $codexHooksPath) { Remove-Item -LiteralPath $codexHooksPath -Force }
    Move-Item -LiteralPath (Join-Path $codexStage 'hooks.json') -Destination $codexHooksPath
    Backup-Item $codexConfigPath 'codex-config.toml'
    if (Test-Path -LiteralPath $codexConfigPath) { Remove-Item -LiteralPath $codexConfigPath -Force }
    Move-Item -LiteralPath $stagedCodexConfig -Destination $codexConfigPath
    $oldClaudeAirules = Join-Path $claudeHome 'airules'
    if (Test-Path -LiteralPath $oldClaudeAirules) {
        $expected = [IO.Path]::GetFullPath($oldClaudeAirules).TrimEnd('\','/')
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $oldClaudeAirules).Path).TrimEnd('\','/')
        $claudeRoot = [IO.Path]::GetFullPath($claudeHome).TrimEnd('\','/')
        if (($resolved -ne $expected) -or -not $resolved.StartsWith($claudeRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing unsafe old airules deletion: $resolved" }
        Backup-Item $oldClaudeAirules 'claude-old-airules'; Remove-Item -LiteralPath $oldClaudeAirules -Recurse -Force
    }
    $artifacts = @()
    foreach ($skill in $skills) { $artifacts += [pscustomobject]@{ target = (Join-Path $skillsHome "$($skill.Name)\SKILL.md"); source = $skill.RelativeSource; sha256 = (Get-Sha256 (Join-Path $skillsHome "$($skill.Name)\SKILL.md")) } }
    $artifacts += [pscustomobject]@{ target = (Join-Path $codexHome 'AGENTS.md'); source = 'Codex/AGENTS.md'; sha256 = (Get-Sha256 (Join-Path $codexHome 'AGENTS.md')) }
    $artifacts += [pscustomobject]@{ target = (Join-Path $claudeHome 'AGENTS.md'); source = 'Codex/AGENTS.md (Claude Skill references)'; sha256 = (Get-Sha256 (Join-Path $claudeHome 'AGENTS.md')) }
    $manifest = [pscustomobject]@{ schemaVersion = 1; deployedAt = $stamp; managedSkills = @($skills.Name); artifacts = $artifacts }
    Backup-Item $manifestPath 'claude-airules-deployment-manifest.json'
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), $utf8)
    Remove-Item -LiteralPath $codexStage,$claudeStage -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "SUCCESS: deployed $($skills.Count) Claude Skills and $($skills.Count) Codex rules; managed Claude/Codex hooks."
    Write-Host "Backed up items: $backupCount"
    Write-Host "Backup directory: $(if (Test-Path -LiteralPath $backupRoot) { $backupRoot } else { '(none)' })"
    if ($warnings.Count) { Write-Host 'Warnings:'; $warnings | ForEach-Object { Write-Host "  - $_" } }
    exit 0
} catch {
    Write-Error "FAILURE: $($_.Exception.Message)" -ErrorAction Continue
    Write-Host "Backed up items before failure: $backupCount"
    Write-Host "Backup directory: $(if (Test-Path -LiteralPath $backupRoot) { $backupRoot } else { '(none)' })"
    if ($warnings.Count) { Write-Host 'Warnings:'; $warnings | ForEach-Object { Write-Host "  - $_" } }
    exit 1
}
