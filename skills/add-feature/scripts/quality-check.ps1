#Requires -Version 5.1
<#
.SYNOPSIS
  プロジェクト種別を自動判別して lint / 型チェック / テストを実行する。

.DESCRIPTION
  package.json / pyproject.toml の有無とその内容から実行すべきコマンドを決める。
  存在しないものは実行せず SKIP として報告する（新しいツールを勝手に導入しない）。
  すべての結果を JSON で返す。1つ失敗しても残りを実行し、全体像を1回で返す。

.PARAMETER SkipTests
  テストだけ飛ばす（実装途中の lint / 型だけ見たいとき）。

.OUTPUTS
  JSON。checks[] に name / command / status(PASS|FAIL|SKIP) / exitCode / reason、
  および allGreen（FAIL が1つも無く、PASS が1つ以上あるか）。
#>
[CmdletBinding()]
param(
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$checks = @()

function Add-Check {
    param(
        [string]$Name,
        [string]$Command,
        [string]$Status,
        $ExitCode = $null,
        [string]$Reason = ''
    )
    $script:checks += [ordered]@{
        name     = $Name
        command  = $Command
        status   = $Status
        exitCode = $ExitCode
        reason   = $Reason
    }
}

function Invoke-Check {
    param(
        [string]$Name,
        [string]$Exe,
        [string[]]$CmdArgs
    )
    $display = ($Exe + ' ' + ($CmdArgs -join ' ')).Trim()
    Write-Output "--- $Name : $display"
    & $Exe @CmdArgs
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        Add-Check -Name $Name -Command $display -Status 'PASS' -ExitCode $code
    } else {
        Add-Check -Name $Name -Command $display -Status 'FAIL' -ExitCode $code
    }
}

function Test-CommandExists {
    param([string]$Name)
    try { $null = Get-Command $Name -ErrorAction Stop; return $true } catch { return $false }
}

$hasNode = Test-Path -LiteralPath 'package.json'
$hasPy = Test-Path -LiteralPath 'pyproject.toml'

if (-not $hasNode -and -not $hasPy) {
    Add-Check -Name 'detect' -Command '' -Status 'SKIP' -Reason 'package.json も pyproject.toml も見つかりません。手動で品質チェックを行ってください。'
}

# ---------------- Node / npm ----------------
if ($hasNode) {
    if (-not (Test-CommandExists 'npm')) {
        Add-Check -Name 'node' -Command 'npm' -Status 'SKIP' -Reason 'npm が見つかりません。'
    } else {
        $pkg = $null
        try { $pkg = Get-Content -LiteralPath 'package.json' -Raw | ConvertFrom-Json } catch {
            Add-Check -Name 'node:parse' -Command 'package.json' -Status 'SKIP' -Reason 'package.json を解析できませんでした。'
        }

        $scriptNames = @()
        if ($null -ne $pkg -and $null -ne $pkg.PSObject.Properties['scripts'] -and $null -ne $pkg.scripts) {
            $scriptNames = @($pkg.scripts.PSObject.Properties.Name)
        }

        if ($scriptNames -contains 'lint') {
            Invoke-Check -Name 'lint' -Exe 'npm' -CmdArgs @('run', 'lint')
        } else {
            Add-Check -Name 'lint' -Command 'npm run lint' -Status 'SKIP' -Reason 'package.json に lint スクリプトがありません。'
        }

        if (Test-Path -LiteralPath 'tsconfig.json') {
            Invoke-Check -Name 'typecheck' -Exe 'npx' -CmdArgs @('tsc', '--noEmit')
        } else {
            Add-Check -Name 'typecheck' -Command 'npx tsc --noEmit' -Status 'SKIP' -Reason 'tsconfig.json がありません。'
        }

        if ($SkipTests) {
            Add-Check -Name 'test' -Command 'npm test' -Status 'SKIP' -Reason '-SkipTests が指定されました。'
        } elseif ($scriptNames -contains 'test') {
            Invoke-Check -Name 'test' -Exe 'npm' -CmdArgs @('test')
        } else {
            Add-Check -Name 'test' -Command 'npm test' -Status 'SKIP' -Reason 'package.json に test スクリプトがありません。'
        }
    }
}

# ---------------- Python / uv ----------------
if ($hasPy) {
    if (-not (Test-CommandExists 'uv')) {
        Add-Check -Name 'python' -Command 'uv' -Status 'SKIP' -Reason 'uv が見つかりません。'
    } else {
        $pyproject = ''
        try { $pyproject = Get-Content -LiteralPath 'pyproject.toml' -Raw } catch { $pyproject = '' }

        $hasRuff = ($pyproject -match 'ruff') -or (Test-Path -LiteralPath 'ruff.toml') -or (Test-Path -LiteralPath '.ruff.toml')
        if ($hasRuff) {
            Invoke-Check -Name 'lint' -Exe 'uv' -CmdArgs @('run', 'ruff', 'check', '.')
            Invoke-Check -Name 'format' -Exe 'uv' -CmdArgs @('run', 'ruff', 'format', '--check', '.')
        } else {
            Add-Check -Name 'lint' -Command 'uv run ruff check .' -Status 'SKIP' -Reason 'ruff の設定が見つかりません。'
        }

        if ($pyproject -match 'mypy') {
            Invoke-Check -Name 'typecheck' -Exe 'uv' -CmdArgs @('run', 'mypy', '.')
        } elseif ($pyproject -match 'pyright') {
            Invoke-Check -Name 'typecheck' -Exe 'uv' -CmdArgs @('run', 'pyright')
        } else {
            Add-Check -Name 'typecheck' -Command 'uv run mypy .' -Status 'SKIP' -Reason 'mypy / pyright の設定が見つかりません。'
        }

        if ($SkipTests) {
            Add-Check -Name 'test' -Command 'uv run pytest -q' -Status 'SKIP' -Reason '-SkipTests が指定されました。'
        } elseif (($pyproject -match 'pytest') -or (Test-Path -LiteralPath 'tests')) {
            Invoke-Check -Name 'test' -Exe 'uv' -CmdArgs @('run', 'pytest', '-q')
        } else {
            Add-Check -Name 'test' -Command 'uv run pytest -q' -Status 'SKIP' -Reason 'pytest の設定も tests/ もありません。'
        }
    }
}

$failed = @($checks | Where-Object { $_.status -eq 'FAIL' })
$passed = @($checks | Where-Object { $_.status -eq 'PASS' })

$summary = [ordered]@{
    allGreen = ($failed.Count -eq 0 -and $passed.Count -gt 0)
    passed   = $passed.Count
    failed   = $failed.Count
    skipped  = @($checks | Where-Object { $_.status -eq 'SKIP' }).Count
    checks   = $checks
}

Write-Output '--- RESULT JSON'
$summary | ConvertTo-Json -Depth 5
