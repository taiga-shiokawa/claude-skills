#Requires -Version 5.1
<#
.SYNOPSIS
  gas-dev phase detection. Returns the project's progress state as one JSON.

.DESCRIPTION
  Inspects the current directory for the artifacts each phase leaves behind
  (.clasp.json, docs/business-understanding.md, CLAUDE.md + docs/, .steering/)
  and suggests which phase to start from. The suggestion is a heuristic; the
  caller may override it based on what the user asked for.

.OUTPUTS
  JSON: hasClaspJson / scriptId / hasIdeaDoc / hasBizDoc / hasClaudeMd /
  docsCount / docsFiles / steeringDirs / isGitRepo / suggestedPhase / notes
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$result = [ordered]@{
    hasClaspJson   = $false
    scriptId       = $null
    hasIdeaDoc     = $false
    hasBizDoc      = $false
    hasClaudeMd    = $false
    docsCount      = 0
    docsFiles      = @()
    steeringDirs   = @()
    isGitRepo      = $false
    suggestedPhase = $null
    notes          = @()
}

if (Test-Path '.clasp.json') {
    $result.hasClaspJson = $true
    try {
        $cfg = Get-Content '.clasp.json' -Raw | ConvertFrom-Json
        $result.scriptId = $cfg.scriptId
    } catch {
        $result.notes += 'Could not parse .clasp.json.'
    }
}

$result.hasIdeaDoc = [bool](Test-Path 'docs/idea.md')
$result.hasBizDoc = [bool](Test-Path 'docs/business-understanding.md')
$result.hasClaudeMd = [bool](Test-Path 'CLAUDE.md')

if (Test-Path 'docs') {
    $docs = @(Get-ChildItem 'docs' -Filter '*.md' -File)
    $result.docsCount = $docs.Count
    $result.docsFiles = @($docs | ForEach-Object { $_.Name })
}

if (Test-Path '.steering') {
    $result.steeringDirs = @(Get-ChildItem '.steering' -Directory | ForEach-Object { $_.Name })
}

try {
    $null = Get-Command git -ErrorAction Stop
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) { $result.isGitRepo = $true }
} catch {}

# Heuristic: pick the first phase whose artifact is missing.
if (-not $result.hasClaspJson) {
    $result.suggestedPhase = '1-gas-clone'
} elseif (-not $result.hasBizDoc) {
    $result.suggestedPhase = '2-business-understanding'
} elseif (-not ($result.hasClaudeMd -and $result.docsCount -ge 3)) {
    $result.suggestedPhase = '3-dev-docs-init'
    $result.notes += 'docs/ exists but the permanent doc set looks incomplete (expecting CLAUDE.md plus the dev-docs files).'
} else {
    $result.suggestedPhase = '4-add-feature-or-5-gas-push'
    $result.notes += 'Setup and docs exist. Phase 4 (add-feature) for new work; phase 5 (gas-push) if an implemented change has not been pushed yet.'
}

$result | ConvertTo-Json -Depth 4
exit 0
