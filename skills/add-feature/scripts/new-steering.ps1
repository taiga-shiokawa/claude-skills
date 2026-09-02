#Requires -Version 5.1
<#
.SYNOPSIS
  ステアリングディレクトリを実行時日付で作成する。

.DESCRIPTION
  .steering/<yyyyMMdd>-<Title>/ を作成する。日付をスクリプト側で解決することで、
  プレースホルダ（[YYYYMMDD]）がそのままディレクトリ名になる事故を防ぐ。
  カレントディレクトリがプロジェクトルートであることを前提とする。

  dev-docs スキルの同名スクリプトと同一内容。スキル間を絶対パスで参照すると
  参照元の移動で静かに壊れるため、意図的に複製している。

.PARAMETER Title
  開発タイトル。英語ケバブケース推奨（例: add-tag-feature）。

.OUTPUTS
  CREATED<TAB><path>  ディレクトリを作成した
  EXISTS<TAB><path>   既に存在するため作成しなかった
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Title
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Title が空です。開発タイトルを渡してください。"
    exit 1
}

if ($Title -match '[\[\]<>]') {
    Write-Error "Title にプレースホルダ文字 ([ ] < >) が含まれています: '$Title'。実際の開発タイトルに置き換えてください。"
    exit 1
}

if ($Title -match '[\\/]') {
    Write-Error "Title にパス区切り文字が含まれています: '$Title'。"
    exit 1
}

$date = Get-Date -Format 'yyyyMMdd'
$path = Join-Path '.steering' "$date-$Title"

if (Test-Path -LiteralPath $path) {
    Write-Output "EXISTS`t$path"
    Write-Output "既存のステアリングディレクトリです。上書きせず、新規作業なら別のタイトルを使ってください。"
    exit 0
}

New-Item -ItemType Directory -Force -Path $path | Out-Null
Write-Output "CREATED`t$path"
