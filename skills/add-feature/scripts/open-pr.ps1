#Requires -Version 5.1
<#
.SYNOPSIS
  Pull Request を作成する。本文はファイル渡し。

.DESCRIPTION
  本文を -BodyFile で受け取り gh pr create --body-file に渡す。
  bash heredoc を使わないため PowerShell でそのまま動く。
  マージはこのスクリプトでは行わない（merge-pr.ps1 が担当）。

.PARAMETER Title
  PR タイトル。

.PARAMETER BodyFile
  PR 本文の Markdown ファイルパス。

.PARAMETER Base
  マージ先ブランチ。既定は main。

.OUTPUTS
  JSON。number / url / base / head / notes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$BodyFile,

    [string]$Base = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$notes = @()

if (-not (Test-Path -LiteralPath $BodyFile)) {
    Write-Error "本文ファイルが見つかりません: $BodyFile"
    exit 1
}
if ($Title -match '[<>]') {
    Write-Error "Title にプレースホルダ文字 (< >) が残っています: '$Title'"
    exit 1
}

$head = git rev-parse --abbrev-ref HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Error "現在のブランチを取得できません。"
    exit 1
}
$head = $head.Trim()

if ($head -eq $Base) {
    Write-Error "現在のブランチが base と同じ ('$Base') です。作業ブランチから実行してください。"
    exit 1
}

# push 済みでないと PR を作れない
$null = git rev-parse --verify --quiet "refs/remotes/origin/$head"
if ($LASTEXITCODE -ne 0) {
    Write-Error "'origin/$head' が見つかりません。先に commit-and-push.ps1 で push してください。"
    exit 1
}

$out = gh pr create --base $Base --title $Title --body-file $BodyFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "gh pr create に失敗しました。既に PR が存在する可能性があります（gh pr view で確認してください）。"
    exit 1
}

$url = ($out | Where-Object { $_ -match 'https?://' } | Select-Object -Last 1)
if ($null -ne $url) { $url = $url.Trim() }

$number = $null
if ($null -ne $url -and $url -match '/pull/(\d+)\s*$') {
    $number = [int]$Matches[1]
} else {
    $notes += "PR 番号を URL から取得できませんでした。gh の出力: $($out -join ' / ')"
}

[ordered]@{
    number = $number
    url    = $url
    base   = $Base
    head   = $head
    notes  = $notes
} | ConvertTo-Json -Depth 3
