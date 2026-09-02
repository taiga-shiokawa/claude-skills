#Requires -Version 5.1
<#
.SYNOPSIS
  デフォルトブランチを最新化してから作業ブランチを切る。

.DESCRIPTION
  main 上で直接実装しないためのスクリプト。<Prefix>/<Title> のブランチを作成する。
  未コミットの変更がある場合は、切り替えで失われる恐れがあるため中断する。

.PARAMETER Prefix
  ブランチ名の prefix（feat / fix / docs など）。development-guidelines.md の Git 規約に従う。

.PARAMETER Title
  開発タイトル。英語ケバブケース推奨。

.PARAMETER BaseBranch
  最新化して分岐元にするブランチ。既定は main。

.OUTPUTS
  CREATED<TAB><branch>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$BaseBranch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if ($Title -match '[\[\]<>]' -or $Prefix -match '[\[\]<>]') {
    Write-Error "Prefix / Title にプレースホルダ文字 ([ ] < >) が含まれています。実際の値に置き換えてください。"
    exit 1
}

$branch = "$Prefix/$Title"

# 未コミットの変更があるまま switch すると作業を失う恐れがある
$porcelain = git status --porcelain
if ($LASTEXITCODE -ne 0) {
    Write-Error "git status に失敗しました。git リポジトリ内で実行してください。"
    exit 1
}
if (-not [string]::IsNullOrWhiteSpace($porcelain)) {
    Write-Error "未コミットの変更があります。commit / stash してから実行してください:`n$porcelain"
    exit 1
}

# 既存ブランチを潰さない
$null = git rev-parse --verify --quiet "refs/heads/$branch"
if ($LASTEXITCODE -eq 0) {
    Write-Error "ブランチ '$branch' は既に存在します。別のタイトルを使うか、既存ブランチに switch してください。"
    exit 1
}

git switch $BaseBranch
if ($LASTEXITCODE -ne 0) {
    Write-Error "'$BaseBranch' への switch に失敗しました。"
    exit 1
}

git pull --ff-only
if ($LASTEXITCODE -ne 0) {
    Write-Error "'$BaseBranch' の pull --ff-only に失敗しました。ローカルが分岐している可能性があります。"
    exit 1
}

git switch -c $branch
if ($LASTEXITCODE -ne 0) {
    Write-Error "ブランチ '$branch' の作成に失敗しました。"
    exit 1
}

Write-Output "CREATED`t$branch"
