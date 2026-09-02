#Requires -Version 5.1
<#
.SYNOPSIS
  add-feature の Step 0 前提チェック。gh / git の状態を1つの JSON で返す。

.DESCRIPTION
  gh の導入・認証、GitHub リモートかどうか、作業ツリーの汚れを1回で調べる。
  個別コマンドの生出力をメインコンテキストに載せないことが目的。
  失敗を例外にせず、判定結果として JSON に載せて返す（呼び出し側が分岐する）。

.OUTPUTS
  JSON。ghInstalled / ghAuthed / isGitRepo / isGitHub / nameWithOwner /
  defaultBranch / currentBranch / dirty / dirtyFiles
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
# gh / git の非0終了は「判定結果」なので、ここでは停止させない
$ErrorActionPreference = 'Continue'

function Test-CommandExists {
    param([string]$Name)
    try {
        $null = Get-Command $Name -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

$result = [ordered]@{
    ghInstalled   = $false
    ghAuthed      = $false
    isGitRepo     = $false
    isGitHub      = $false
    nameWithOwner = $null
    defaultBranch = $null
    currentBranch = $null
    dirty         = $false
    dirtyFiles    = @()
    notes         = @()
}

# --- git ---
if (-not (Test-CommandExists 'git')) {
    $result.notes += 'git が見つかりません。'
} else {
    $null = git rev-parse --is-inside-work-tree
    if ($LASTEXITCODE -eq 0) {
        $result.isGitRepo = $true

        $branch = git rev-parse --abbrev-ref HEAD
        if ($LASTEXITCODE -eq 0) { $result.currentBranch = $branch.Trim() }

        $porcelain = git status --porcelain
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($porcelain)) {
            $result.dirty = $true
            $result.dirtyFiles = @($porcelain -split "`r?`n" | Where-Object { $_ -ne '' })
        }
    } else {
        $result.notes += 'git リポジトリではありません。'
    }
}

# --- gh ---
if (-not (Test-CommandExists 'gh')) {
    $result.notes += 'gh CLI が見つかりません。Issue / PR の工程はスキップしてください。'
} else {
    $result.ghInstalled = $true

    $null = gh auth status
    if ($LASTEXITCODE -eq 0) {
        $result.ghAuthed = $true
    } else {
        $result.notes += 'gh が未認証です。Issue / PR の工程はスキップしてください。'
    }

    if ($result.ghAuthed -and $result.isGitRepo) {
        $json = gh repo view --json nameWithOwner,defaultBranchRef
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($json)) {
            try {
                $repo = $json | ConvertFrom-Json
                $result.isGitHub = $true
                $result.nameWithOwner = $repo.nameWithOwner
                if ($null -ne $repo.defaultBranchRef) {
                    $result.defaultBranch = $repo.defaultBranchRef.name
                }
            } catch {
                $result.notes += 'gh repo view の JSON を解析できませんでした。'
            }
        } else {
            $result.notes += 'リモートが GitHub ではないか、リポジトリを解決できません。Issue / PR の工程はスキップしてください。'
        }
    }
}

$result | ConvertTo-Json -Depth 4
