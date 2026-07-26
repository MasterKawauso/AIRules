# AIRULES-MANAGED-HOOK schema=1 source=Claude/hooks/require_agent_model.ps1
# PreToolUse gate for the Agent tool.
# WORKFLOW.md requires the owner AI / model / thinking depth to be settled before
# design, implementation or review work is delegated. A missing `model` makes the
# subagent inherit the parent model (opus), which is how an unattended run can
# burn a large token budget. Deny the call until the model is stated explicitly.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-Allow {
    (@{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'allow' } } | ConvertTo-Json -Compress -Depth 5)
    exit 0
}

$raw = [Console]::In.ReadToEnd()
# Fail open: a malformed payload must never block ordinary work.
if ([string]::IsNullOrWhiteSpace($raw)) { Write-Allow }
try { $payload = $raw | ConvertFrom-Json } catch { Write-Allow }
if ($payload.tool_name -ne 'Agent') { Write-Allow }

$toolInput = $payload.tool_input
$model = if ($toolInput -and $toolInput.PSObject.Properties.Name -contains 'model') { [string]$toolInput.model } else { '' }
$agent = if ($toolInput -and $toolInput.PSObject.Properties.Name -contains 'subagent_type') { [string]$toolInput.subagent_type } else { '' }

# Model stated explicitly: the cost is a deliberate choice, so let it through.
if (-not [string]::IsNullOrWhiteSpace($model)) { Write-Allow }

# Cheap or read-only agents cannot cause the runaway this gate exists to prevent.
$exempt = @('Explore', 'statusline-setup', 'claude-code-guide')
if ($exempt -contains $agent) { Write-Allow }

$label = if ([string]::IsNullOrWhiteSpace($agent)) { 'general-purpose' } else { $agent }
$reason = @"
Agent起動を停止した: model未指定（subagent_type=$label）。

model省略時は親モデル(opus)を継承し、想定外のトークン消費になる。WORKFLOW.mdの
着手前ゲートに従い、次のどちらかを行う。

1. ユーザーへ推奨モデルと品質・費用・時間の差を示し、回答を待つ
2. 既に指定がある場合は Agent の model 引数に明示して再実行する
   （haiku=軽量・安価 / sonnet=標準 / opus=高難度のみ）

調査だけで足りるなら subagent_type=Explore を使う（このゲートの対象外）。
"@

(@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason
    }
    systemMessage = "AIRules: Agent(subagent_type=$label) をmodel未指定のため停止した。"
} | ConvertTo-Json -Compress -Depth 5)
exit 0
