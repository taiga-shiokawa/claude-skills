#Requires -Version 5.1
<#
.SYNOPSIS
  ガードを全て通過した場合にのみ PR を main へマージする。

.DESCRIPTION
  add-feature の「マージを止める条件」をスクリプト側の門番として実装する。

  スクリプトが自分で検証できるもの:
    - CI チェックが失敗 / pending
    - コンフリクト（mergeable != MERGEABLE）
    - ブランチ保護・レビュー必須によるブロック（mergeStateStatus）

  スクリプトが検証できないもの（呼び出し側が明示的に主張する必要がある）:
    - lint / 型 / テストが green か           -> -QualityGreen
    - レビューの Critical / Major が解消済みか -> -ReviewClean

  この2つは既定で「未主張＝マージ拒否」。スイッチを付け忘れたら止まる側に倒している。

.PARAMETER PrNumber
  対象 PR 番号。省略時は現在のブランチに紐づく PR。

.PARAMETER QualityGreen
  lint / 型 / テストがすべて green であることの主張。必須。

.PARAMETER ReviewClean
  Critical / Major の指摘が残っていないことの主張。必須。

.PARAMETER MergeMethod
  merge / squash / rebase。省略時はリポジトリ設定から選ぶ（merge を優先）。

.PARAMETER SkipChecks
  CI チェックの待機を省略する（CI が無いリポジトリ向け）。

.OUTPUTS
  JSON。merged / reason / prNumber / mergeMethod / issueClosed / notes
#>
[CmdletBinding()]
param(
    [int]$PrNumber = 0,

    [switch]$QualityGreen,

    [switch]$ReviewClean,

    [ValidateSet('merge', 'squash', 'rebase')]
    [string]$MergeMethod,

    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$notes = @()

function Deny {
    param([string]$Reason)
    [ordered]@{
        merged      = $false
        reason      = $Reason
        prNumber    = $script:PrNumber
        mergeMethod = $null
        issueClosed = $null
        notes       = $script:notes
    } | ConvertTo-Json -Depth 3
    exit 1
}

# --- 呼び出し側が主張すべきガード ---
if (-not $QualityGreen) {
    Deny '品質チェックが green であるという主張 (-QualityGreen) がありません。lint / 型 / テストを確認してから付けてください。'
}
if (-not $ReviewClean) {
    Deny 'レビュー指摘が解消済みという主張 (-ReviewClean) がありません。Critical / Major を潰してから付けてください。'
}

# --- PR の特定 ---
$prJson = $null
if ($PrNumber -gt 0) {
    $prJson = gh pr view $PrNumber --json number,mergeable,mergeStateStatus,state,closingIssuesReferences
} else {
    $prJson = gh pr view --json number,mergeable,mergeStateStatus,state,closingIssuesReferences
}
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($prJson)) {
    Deny 'PR を特定できませんでした。PR が作成されているか確認してください。'
}

$pr = $null
try { $pr = $prJson | ConvertFrom-Json } catch { Deny 'gh pr view の JSON を解析できませんでした。' }
$PrNumber = $pr.number

if ($pr.state -ne 'OPEN') {
    Deny "PR #$PrNumber は OPEN ではありません（state=$($pr.state)）。"
}
if ($pr.mergeable -ne 'MERGEABLE') {
    Deny "PR #$PrNumber はマージ可能な状態ではありません（mergeable=$($pr.mergeable)）。コンフリクトの可能性があります。"
}

$blockedStates = @('BLOCKED', 'DIRTY', 'DRAFT', 'BEHIND')
if ($blockedStates -contains $pr.mergeStateStatus) {
    Deny "PR #$PrNumber はマージがブロックされています（mergeStateStatus=$($pr.mergeStateStatus)）。ブランチ保護・レビュー必須設定・ベース遅れを確認してください。"
}

# --- CI チェック ---
if ($SkipChecks) {
    $notes += '-SkipChecks が指定されたため CI チェックを待機しませんでした。'
} else {
    $null = gh pr checks $PrNumber --watch
    $checksExit = $LASTEXITCODE
    if ($checksExit -eq 8) {
        $notes += 'CI チェックは設定されていませんでした。'
    } elseif ($checksExit -ne 0) {
        Deny "CI チェックが失敗または pending のままです（gh pr checks 終了コード=$checksExit）。"
    }
}

# --- マージ方式 ---
$method = $MergeMethod
if ([string]::IsNullOrWhiteSpace($method)) {
    $repoJson = gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($repoJson)) {
        $repo = $null
        try { $repo = $repoJson | ConvertFrom-Json } catch { $repo = $null }
        if ($null -ne $repo) {
            if ($repo.mergeCommitAllowed) { $method = 'merge' }
            elseif ($repo.squashMergeAllowed) { $method = 'squash' }
            elseif ($repo.rebaseMergeAllowed) { $method = 'rebase' }
        }
    }
    if ([string]::IsNullOrWhiteSpace($method)) {
        $method = 'merge'
        $notes += 'リポジトリのマージ方式を判定できなかったため merge を使いました。'
    }
}

# --- マージ ---
gh pr merge $PrNumber "--$method" --delete-branch
if ($LASTEXITCODE -ne 0) {
    Deny "gh pr merge に失敗しました（method=$method）。"
}

# --- ベースブランチを最新化 ---
git switch main
if ($LASTEXITCODE -eq 0) {
    git pull --ff-only
    if ($LASTEXITCODE -ne 0) { $notes += 'main の pull --ff-only に失敗しました。' }
} else {
    $notes += 'main への switch に失敗しました。'
}

# --- 紐づく Issue が閉じたか確認 ---
$issueClosed = $null
if ($null -ne $pr.closingIssuesReferences -and @($pr.closingIssuesReferences).Count -gt 0) {
    $issueClosed = @()
    foreach ($iss in @($pr.closingIssuesReferences)) {
        $stateJson = gh issue view $iss.number --json number,state
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($stateJson)) {
            try {
                $st = $stateJson | ConvertFrom-Json
                $issueClosed += [ordered]@{ number = $st.number; state = $st.state }
                if ($st.state -ne 'CLOSED') {
                    $notes += "Issue #$($st.number) が閉じていません。gh issue close $($st.number) で閉じてください。"
                }
            } catch { $notes += "Issue #$($iss.number) の状態を解析できませんでした。" }
        }
    }
} else {
    $notes += 'PR に紐づく Issue が検出されませんでした（本文の Closes #N を確認してください）。'
}

[ordered]@{
    merged      = $true
    reason      = $null
    prNumber    = $PrNumber
    mergeMethod = $method
    issueClosed = $issueClosed
    notes       = $notes
} | ConvertTo-Json -Depth 4
