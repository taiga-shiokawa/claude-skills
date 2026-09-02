#Requires -Version 5.1
<#
.SYNOPSIS
  変更を commit して現在のブランチを push する。メッセージはファイル渡し。

.DESCRIPTION
  コミットメッセージを -MessageFile で受け取り、git commit -F に渡す。
  bash heredoc を使わないため PowerShell でそのまま動く。
  ステージ内容に機密ファイルらしき名前が含まれていたら中断する（名前ベースの検査）。
  main / master への直接コミットは拒否する。

.PARAMETER MessageFile
  コミットメッセージのファイルパス。

.PARAMETER Paths
  ステージするパス。省略時は追跡済みの変更すべて（git add -A）。

.PARAMETER AllowSecretNames
  機密ファイル名の検査を承知の上で通す（既定では中断する）。

.OUTPUTS
  JSON。branch / sha / staged[] / pushed / notes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MessageFile,

    [string[]]$Paths,

    [switch]$AllowSecretNames
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$notes = @()

if (-not (Test-Path -LiteralPath $MessageFile)) {
    Write-Error "コミットメッセージのファイルが見つかりません: $MessageFile"
    exit 1
}

$branch = git rev-parse --abbrev-ref HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Error "現在のブランチを取得できません。git リポジトリ内で実行してください。"
    exit 1
}
$branch = $branch.Trim()

if ($branch -in @('main', 'master')) {
    Write-Error "'$branch' に直接コミットしようとしています。作業ブランチを切ってから実行してください。"
    exit 1
}

# ステージする
if ($null -ne $Paths -and $Paths.Count -gt 0) {
    git add -- @Paths
} else {
    git add -A
}
if ($LASTEXITCODE -ne 0) {
    Write-Error "git add に失敗しました。"
    exit 1
}

$staged = @(git diff --cached --name-only | Where-Object { $_ -ne '' })
if ($LASTEXITCODE -ne 0) {
    Write-Error "ステージ内容の取得に失敗しました。"
    exit 1
}
if ($staged.Count -eq 0) {
    Write-Output '{"pushed":false,"notes":["ステージされた変更がありません。コミットは行いませんでした。"]}'
    exit 0
}

# 機密ファイルらしき名前を検査する（内容ではなく名前の検査であることに注意）
$secretPattern = '(^|/)\.env($|\.)|\.pem$|\.p12$|\.pfx$|(^|/)id_rsa|(^|/)id_ed25519|\.key$|(^|/)credentials\.json$|(^|/)service-account.*\.json$'
$suspicious = @($staged | Where-Object { $_ -match $secretPattern })
if ($suspicious.Count -gt 0) {
    if (-not $AllowSecretNames) {
        git reset | Out-Null
        Write-Error "機密ファイルらしき名前がステージされています。ステージを解除しました:`n$($suspicious -join "`n")`n意図的なら -AllowSecretNames を付けて再実行してください。"
        exit 1
    }
    $notes += "機密ファイルらしき名前を -AllowSecretNames で通しました: $($suspicious -join ', ')"
}

git commit -F $MessageFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "git commit に失敗しました。"
    exit 1
}

$sha = git rev-parse --short HEAD
if ($LASTEXITCODE -eq 0) { $sha = $sha.Trim() } else { $sha = $null }

git push -u origin $branch
$pushed = ($LASTEXITCODE -eq 0)
if (-not $pushed) {
    $notes += 'git push に失敗しました。コミットはローカルに残っています。'
}

[ordered]@{
    branch = $branch
    sha    = $sha
    staged = $staged
    pushed = $pushed
    notes  = $notes
} | ConvertTo-Json -Depth 3
