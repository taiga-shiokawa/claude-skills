#Requires -Version 5.1
<#
.SYNOPSIS
  GitHub Issue を起票する。本文はファイル渡し。

.DESCRIPTION
  本文を -BodyFile で受け取ることで、bash heredoc も PowerShell の引用符地獄も回避する。
  呼び出し側は本文を一時ファイルに書き出してからパスを渡すこと。
  ラベルは gh label list に存在するものだけを付ける（存在しないラベルは新規作成せず、警告して無視する）。

.PARAMETER Title
  Issue タイトル。

.PARAMETER BodyFile
  Issue 本文の Markdown ファイルパス。

.PARAMETER Label
  付けたいラベル名。省略可。存在しない場合は付けずに続行する。

.OUTPUTS
  JSON。number / url / label（実際に付いたもの）/ notes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$BodyFile,

    [string]$Label
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

$bodyRaw = Get-Content -LiteralPath $BodyFile -Raw
if ($bodyRaw -match '[<>]' -and $bodyRaw -match '<[^>\r\n]{1,40}>') {
    $notes += '本文にプレースホルダらしき <...> が残っています。意図したものか確認してください。'
}

$ghArgs = @('issue', 'create', '--title', $Title, '--body-file', $BodyFile)

$appliedLabel = $null
if (-not [string]::IsNullOrWhiteSpace($Label)) {
    $labelJson = gh label list --json name --limit 200
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($labelJson)) {
        $existing = @()
        try { $existing = @(($labelJson | ConvertFrom-Json).name) } catch { $existing = @() }
        if ($existing -contains $Label) {
            $ghArgs += @('--label', $Label)
            $appliedLabel = $Label
        } else {
            $notes += "ラベル '$Label' はリポジトリに存在しないため付けませんでした（新規作成もしていません）。既存: $($existing -join ', ')"
        }
    } else {
        $notes += 'gh label list に失敗したため、ラベルを付けずに起票しました。'
    }
}

$out = gh @ghArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "gh issue create に失敗しました。"
    exit 1
}

# gh は作成した Issue の URL を stdout に返す
$url = ($out | Where-Object { $_ -match 'https?://' } | Select-Object -Last 1)
if ($null -ne $url) { $url = $url.Trim() }

$number = $null
if ($null -ne $url -and $url -match '/issues/(\d+)\s*$') {
    $number = [int]$Matches[1]
} else {
    $notes += "Issue 番号を URL から取得できませんでした。gh の出力: $($out -join ' / ')"
}

[ordered]@{
    number = $number
    url    = $url
    label  = $appliedLabel
    notes  = $notes
} | ConvertTo-Json -Depth 3
