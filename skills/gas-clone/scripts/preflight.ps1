#Requires -Version 5.1
<#
.SYNOPSIS
  gas-clone Step 0 preflight. Returns clasp/auth/directory state as one JSON.

.DESCRIPTION
  Checks clasp installation, login state, an existing .clasp.json, and whether
  the current directory is empty. Failures are reported as JSON fields rather
  than exceptions so the caller can branch on them.

.OUTPUTS
  JSON: claspInstalled / claspVersion / loggedIn / authUser / hasClaspJson /
  existingScriptId / dirEntryCount / dirEntries / isGitRepo / notes
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
# Non-zero exits from native commands are verdicts here, not errors.
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Test-CommandExists {
    param([string]$Name)
    try { $null = Get-Command $Name -ErrorAction Stop; return $true } catch { return $false }
}

$result = [ordered]@{
    claspInstalled   = $false
    claspVersion     = $null
    loggedIn         = $false
    authUser         = $null
    hasClaspJson     = $false
    existingScriptId = $null
    dirEntryCount    = 0
    dirEntries       = @()
    isGitRepo        = $false
    notes            = @()
}

# --- clasp ---
if (-not (Test-CommandExists 'clasp')) {
    $result.notes += 'clasp not found. Suggest: npm install -g @google/clasp'
} else {
    $result.claspInstalled = $true

    $v = clasp --version
    if ($LASTEXITCODE -eq 0 -and $v) { $result.claspVersion = ("$v").Trim() }

    $authOut = (clasp show-authorized-user | Out-String)
    if ($LASTEXITCODE -eq 0 -and $authOut -match 'logged in as\s+(\S+)') {
        $result.loggedIn = $true
        $result.authUser = $Matches[1].TrimEnd('.')
    } else {
        $result.notes += 'Not logged in to clasp. The USER must run: clasp login (browser auth must not be done by Claude).'
    }
}

# --- current directory ---
if (Test-Path '.clasp.json') {
    $result.hasClaspJson = $true
    try {
        $cfg = Get-Content '.clasp.json' -Raw | ConvertFrom-Json
        $result.existingScriptId = $cfg.scriptId
    } catch {
        $result.notes += 'Could not parse .clasp.json.'
    }
}

$entries = @(Get-ChildItem -Force | Where-Object { $_.Name -notin @('.claude', '.git') })
$result.dirEntryCount = $entries.Count
$result.dirEntries = @($entries | Select-Object -First 10 | ForEach-Object { $_.Name })

# --- git ---
if (Test-CommandExists 'git') {
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) { $result.isGitRepo = $true }
}

$result | ConvertTo-Json -Depth 4
exit 0
