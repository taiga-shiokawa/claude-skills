#Requires -Version 5.1
<#
.SYNOPSIS
  Runs clasp push with guards and returns the result as JSON.

.DESCRIPTION
  clasp push OVERWRITES the remote project, so this script refuses to run
  unless -Confirmed is passed. -Confirmed asserts that the caller showed the
  user the filesToPush list and followed the skill's confirmation rules
  (SKILL.md Step 2). Do not pass it otherwise.

  When the remote manifest (appsscript.json) changed, clasp asks an
  interactive question; stdin is not available here, so that surfaces as a
  failed push and is reported as needsForce. Re-run with -Force only after
  the user approved overwriting the remote manifest.

.OUTPUTS
  JSON: pushed / exitCode / needsForce / output / notes
#>
[CmdletBinding()]
param(
    [switch]$Confirmed,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$result = [ordered]@{
    pushed     = $false
    exitCode   = $null
    needsForce = $false
    output     = $null
    notes      = @()
}

if (-not $Confirmed) {
    $result.notes += 'Refusing to push: -Confirmed not set. Show the user the filesToPush list first (SKILL.md Step 2), then re-run with -Confirmed.'
    $result | ConvertTo-Json -Depth 4
    exit 0
}

if (-not (Test-Path '.clasp.json')) {
    $result.notes += 'No .clasp.json in the current directory - nothing to push.'
    $result | ConvertTo-Json -Depth 4
    exit 0
}

if ($Force) {
    $out = (clasp push -f | Out-String)
} else {
    $out = (clasp push | Out-String)
}
$result.exitCode = $LASTEXITCODE

$outTrim = ''
if ($out) { $outTrim = $out.Trim() }
$result.output = $outTrim

if ($LASTEXITCODE -eq 0) {
    $result.pushed = $true
    if ($outTrim -match 'Pushed\s+(\d+)\s+files') {
        $result.notes += ('Pushed file count: ' + $Matches[1])
    }
} else {
    if (-not $Force -and ($outTrim -match 'manifest' -or [string]::IsNullOrWhiteSpace($outTrim))) {
        $result.needsForce = $true
        $result.notes += 'Push did not complete. Likely cause: the interactive confirmation for a changed manifest (appsscript.json), which cannot be answered in this non-interactive shell. Explain the local manifest changes to the user; only after approval re-run with -Confirmed -Force.'
    } else {
        $result.notes += 'clasp push failed. See output (possible causes: syntax error in a source file, access rights, network).'
    }
}

$result | ConvertTo-Json -Depth 4
exit 0
