#Requires -Version 5.1
<#
.SYNOPSIS
  Runs clasp clone with guards. Accepts a raw script ID or an Apps Script URL.

.DESCRIPTION
  Guards: refuses when .clasp.json already exists (already cloned), and when
  the current directory is not empty unless -AllowNonEmpty is passed.
  Returns the result as JSON so raw clasp output stays out of the main context.

.OUTPUTS
  JSON: status (cloned | already_cloned | dir_not_empty | invalid_id | clone_failed)
  / scriptId / filesPulled / files / exitCode / notes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScriptId,
    [string]$RootDir,
    [switch]$AllowNonEmpty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$result = [ordered]@{
    status      = $null
    scriptId    = $null
    filesPulled = 0
    files       = @()
    exitCode    = $null
    notes       = @()
}

# Accept a full editor URL and extract the ID part.
$id = $ScriptId.Trim()
if ($id -match '/projects/([A-Za-z0-9_-]+)') { $id = $Matches[1] }

if ($id -notmatch '^[A-Za-z0-9_-]{20,100}$') {
    $result.status = 'invalid_id'
    $result.notes += "Does not look like a script ID or Apps Script URL: $id"
    $result | ConvertTo-Json -Depth 4
    exit 0
}
$result.scriptId = $id

if (Test-Path '.clasp.json') {
    $result.status = 'already_cloned'
    $result.notes += 'A .clasp.json already exists here. Refusing to clone over an existing project. Use clasp pull (after warning about overwriting local changes) to update it instead.'
    $result | ConvertTo-Json -Depth 4
    exit 0
}

$entries = @(Get-ChildItem -Force | Where-Object { $_.Name -notin @('.claude', '.git') })
if ($entries.Count -gt 0 -and -not $AllowNonEmpty) {
    $result.status = 'dir_not_empty'
    $result.notes += "Current directory has $($entries.Count) entries (e.g. $((@($entries | Select-Object -First 5 | ForEach-Object { $_.Name })) -join ', ')). Confirm with the user, then re-run with -AllowNonEmpty, or clone into a fresh subdirectory."
    $result | ConvertTo-Json -Depth 4
    exit 0
}

if ($RootDir) {
    $out = (clasp clone $id --rootDir $RootDir | Out-String)
} else {
    $out = (clasp clone $id | Out-String)
}
$result.exitCode = $LASTEXITCODE

if ($LASTEXITCODE -ne 0 -or -not (Test-Path '.clasp.json')) {
    $result.status = 'clone_failed'
    $result.notes += 'clasp clone failed. Check the script ID and whether this account can access the project.'
    if ($out -and $out.Trim()) { $result.notes += ('clasp output: ' + $out.Trim()) }
    $result | ConvertTo-Json -Depth 4
    exit 0
}

$result.status = 'cloned'

$statusJson = (clasp status --json | Out-String)
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($statusJson)) {
    try {
        $st = $statusJson | ConvertFrom-Json
        $result.files = @($st.filesToPush)
        $result.filesPulled = @($st.filesToPush).Count
    } catch {
        $result.notes += 'Cloned, but could not parse clasp status output for the file list.'
    }
}

$result | ConvertTo-Json -Depth 4
exit 0
