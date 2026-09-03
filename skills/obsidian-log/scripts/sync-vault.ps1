<#
.SYNOPSIS
    Obsidian 保管庫の未コミット変更を GitHub の Private リポジトリへ同期する。

.DESCRIPTION
    秘密情報スキャン → add → commit → リモートと rebase → push を自動で完走する。
    add -A なので、Codex が書いて未コミットで溜まっているノートも一緒に載る。

    ノートを書くことが主目的で、同期は従属。push に失敗してもノートとローカルコミットは
    残るので、呼び出し側は「ノートは保存済み・push だけ未完了」として報告すること。

.PARAMETER NoteDate
    ノートの日付 (YYYY-MM-DD)。コミットメッセージに使う。

.PARAMETER Title
    ノートのタイトル。コミットメッセージに使う。省略時は件数だけのメッセージになる。

.PARAMETER SkipSecretScan
    秘密情報スキャンを飛ばす。誤検出を人が目で確認した後だけの逃げ道。
    検出された行を直さずに押し通すために使ってはいけない。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File sync-vault.ps1 -NoteDate 2026-09-03 -Title "図鑑パワポのデザイン統一スキル作成"

.NOTES
    終了コード（同期の失敗はノートの失敗ではない。0 以外でもノートは保存済み）:
      0 … 同期完了、または同期する変更が無かった
      2 … 秘密情報を検出。commit も push もしていない（作業ツリーは無傷）
      3 … 保管庫が git リポジトリでない / 別リポジトリの中にある
      4 … 手作業が必要な git の状態（merge・rebase の途中、または rebase 衝突）
      5 … オフライン / push 失敗 / origin 未設定。ローカルコミットは残っている

    このファイルは UTF-8 BOM 付きで保存する。Windows PowerShell 5.1 は BOM の無いファイルを
    ANSI として読むため、BOM を落とすと日本語がすべて壊れてパースエラーになる。
#>
[CmdletBinding()]
param(
    [string]$NoteDate,
    [string]$Title,

    # 保管庫のパス。PC 交換でユーザー名が変わっても追随するよう %USERPROFILE% から組み立てる。
    [string]$Vault = (Join-Path $env:USERPROFILE 'Documents\AI Log'),

    [switch]$DryRun,
    [switch]$SkipSecretScan
)

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 対話プロンプトで固まらせない。新しいPCや認証切れのときに Git Credential Manager の
# GUI が出ると、スキルが無反応のまま待ち続けるのが最悪ケース。即失敗させて報告に回す。
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'never'

# clone 直後でリポジトリ設定が入っていない端末でも効くよう、毎回 -c で渡す。
# core.quotepath=false は全角スペース入りのファイル名を 8 進エスケープにしないため。
$GitCommon = @(
    '-c', 'core.quotepath=false',
    '-c', 'credential.interactive=false',
    '-c', 'i18n.logOutputEncoding=utf-8'
)

function Invoke-Git {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $all = $GitCommon + $Arguments
    $out = & git @all
    $code = $LASTEXITCODE
    if (($code -ne 0) -and (-not $AllowFailure)) {
        throw ("git {0} が失敗しました (exit {1})`n{2}" -f ($Arguments -join ' '), $code, ($out -join "`n"))
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $out }
}

function Test-Reachable {
    # オフライン時に git の HTTP タイムアウトを fetch と push で 2 回待つとユーザーを
    # 数十秒待たせる。TCP を先に叩いて 2 秒で見切る。
    param([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 2000)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $ar = $c.BeginConnect($HostName, $Port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok) {
            try { $c.EndConnect($ar) } catch { $ok = $false }
        }
        $c.Close()
        return $ok
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# 秘密情報のパターン
#
# 誤検出をほぼ出さない高確度なものだけを並べる。最後の汎用ルールは「長い値の代入形」に
# 絞ってあるので、ノートによくある「OPENAI_API_KEY を設定した」のようなキー名だけの
# 記述にはマッチしない（`:` か `=` と 24 文字以上の値が必要）。
# ---------------------------------------------------------------------------
$SecretPatterns = @(
    @{ Name = 'Anthropic API key';  Pattern = 'sk-ant-[A-Za-z0-9\-_]{20,}' },
    @{ Name = 'OpenAI API key';     Pattern = 'sk-[A-Za-z0-9]{20,}' },
    @{ Name = 'GitHub token';       Pattern = 'gh[pousr]_[A-Za-z0-9]{30,}' },
    @{ Name = 'GitHub PAT';         Pattern = 'github_pat_[A-Za-z0-9_]{30,}' },
    @{ Name = 'AWS access key id';  Pattern = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'Google API key';     Pattern = 'AIza[0-9A-Za-z\-_]{35}' },
    @{ Name = 'Slack token';        Pattern = 'xox[baprs]-[A-Za-z0-9-]{10,}' },
    @{ Name = 'Private key block'; Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
    @{ Name = 'JWT';                Pattern = 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.' },
    @{ Name = '長い値の代入';       Pattern = '(?i)(password|passwd|secret|token|api[_-]?key|client[_-]?secret|connection[_-]?string)\s*[:=]\s*["'']?[A-Za-z0-9+/=_\-]{24,}' }
)

$ScanExtensions = @('.md', '.json', '.txt')

function Format-Masked {
    # 値そのものは絶対に出さない。場所が分かれば本人がファイルを開けるので、先頭だけ見せる。
    param([string]$Value)
    $head = $Value
    if ($Value.Length -gt 6) { $head = $Value.Substring(0, 6) }
    return ('{0}***(len={1})' -f $head, $Value.Length)
}

function Get-ChangedPaths {
    $lines = (Invoke-Git @('status', '--porcelain')).Output
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -lt 4) { continue }
        $xy = $line.Substring(0, 2)
        $p = $line.Substring(3)
        if ($xy.StartsWith('R') -or $xy.StartsWith('C')) {
            $arrow = $p.IndexOf(' -> ')
            if ($arrow -ge 0) { $p = $p.Substring($arrow + 4) }
        }
        # 削除は中身が無いのでスキャン対象外（コミット対象には含まれる）
        if (($xy -eq ' D') -or ($xy -eq 'D ') -or ($xy -eq 'DD')) { continue }
        $paths.Add($p)
    }
    return $paths
}

# ---------------------------------------------------------------------------
# 手順
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Vault -PathType Container)) {
    Write-Output ('NOT_A_VAULT: 保管庫が見つかりません: {0}' -f $Vault)
    exit 3
}
if (-not (Test-Path -LiteralPath (Join-Path $Vault '.git'))) {
    Write-Output ('NOT_A_REPO: {0} は git リポジトリではありません。' -f $Vault)
    Write-Output 'ensure-vault-repo.ps1 を先に実行してください（GitHub にリポジトリを作る一回限りの操作です）。'
    exit 3
}

# 非ASCII なユーザー名を含むパスをネイティブ exe の引数に渡すのを避けるため、
# -C ではなく Push-Location を使う。
Push-Location -LiteralPath $Vault
try {

    # 保管庫が「別のリポジトリの中」に置かれていた場合、そのままだと親リポジトリへ
    # コミットしてしまう。トップレベルが保管庫自身であることを確認する。
    $top = ((Invoke-Git @('rev-parse', '--show-toplevel')).Output | Out-String).Trim()
    if ($top) {
        $topResolved = (Resolve-Path -LiteralPath $top).Path.TrimEnd('\')
        $vaultResolved = (Resolve-Path -LiteralPath $Vault).Path.TrimEnd('\')
        if ($topResolved -ne $vaultResolved) {
            Write-Output ('NOT_A_REPO: 保管庫は別のリポジトリ ({0}) の中にあります。' -f $topResolved)
            Write-Output '親リポジトリへコミットしてしまうため中断します。'
            exit 3
        }
    }

    # merge / rebase / cherry-pick の途中には手を出さない。中断状態を悪化させる。
    $gitDir = ((Invoke-Git @('rev-parse', '--git-dir')).Output | Out-String).Trim()
    if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $Vault $gitDir }
    foreach ($marker in @('MERGE_HEAD', 'rebase-merge', 'rebase-apply', 'CHERRY_PICK_HEAD')) {
        if (Test-Path -LiteralPath (Join-Path $gitDir $marker)) {
            Write-Output ('IN_PROGRESS: merge / rebase の途中です ({0})。何も触りません。' -f $marker)
            Write-Output ('  状態を確認: git -C "{0}" status' -f $Vault)
            exit 4
        }
    }

    $changed = Get-ChangedPaths
    if ($changed.Count -eq 0) {
        Write-Output 'NOTHING_TO_COMMIT: 同期する変更はありません。'
        exit 0
    }

    Write-Output ('CHANGED_FILES={0}' -f $changed.Count)
    foreach ($p in $changed) { Write-Output ('  - {0}' -f $p) }

    # 1. 秘密情報スキャン（commit する前に止める。作業ツリーには触らない）
    if ($SkipSecretScan) {
        Write-Output 'WARN: 秘密情報スキャンを飛ばしました (-SkipSecretScan)'
    } else {
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($rel in $changed) {
            $ext = [System.IO.Path]::GetExtension($rel).ToLowerInvariant()
            if ($ScanExtensions -notcontains $ext) { continue }
            $abs = Join-Path $Vault $rel
            if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { continue }
            $lines = [System.IO.File]::ReadAllLines($abs, [System.Text.Encoding]::UTF8)
            for ($i = 0; $i -lt $lines.Length; $i++) {
                foreach ($sp in $SecretPatterns) {
                    $m = [regex]::Match($lines[$i], $sp.Pattern)
                    if ($m.Success) {
                        $hits.Add(('{0}:{1}  [{2}]  {3}' -f $rel, ($i + 1), $sp.Name, (Format-Masked $m.Value)))
                    }
                }
            }
        }
        if ($hits.Count -gt 0) {
            Write-Output ''
            Write-Output ('SECRET_DETECTED={0}' -f $hits.Count)
            foreach ($h in $hits) { Write-Output ('  ! {0}' -f $h) }
            Write-Output ''
            Write-Output 'commit も push もしていません。該当行からキーやトークンの値を削り、'
            Write-Output 'キー名だけの記述に直してから再実行してください。'
            exit 2
        }
        Write-Output 'SECRET_SCAN=clean'
    }

    if ($DryRun) {
        Write-Output ''
        Write-Output 'DRYRUN: ここで add / commit / push を行います。実行するには -DryRun を外してください。'
        exit 0
    }

    # 2. ステージング。全角スペース入りのファイル名でも add -A なら安全。
    # codex-skills は .gitignore で除外しているが、pathspec でも明示的に外す。
    # .gitignore が消えたり編集を誤った場合でも、壊れた gitlink を作らないための二重の防御。
    Invoke-Git @('add', '-A', '--', '.', ':(exclude)codex-skills') | Out-Null

    # 3. コミット
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $subject = ('chore: sync vault ({0} files)' -f $changed.Count)
    } else {
        $datePart = $NoteDate
        if ([string]::IsNullOrWhiteSpace($datePart)) { $datePart = (Get-Date -Format 'yyyy-MM-dd') }
        $subject = ('log: {0} {1}' -f $datePart, $Title)
    }

    # 日本語のコミットメッセージは -m で渡さない。PS 5.1 はネイティブ exe への引数を
    # ANSI コードページで渡す経路があり化ける。UTF-8 のファイルに書いて -F で渡す。
    # 置き場所は .git 配下（追跡されない）にし、git へは相対の ASCII パスで渡す。
    $msgAbs = Join-Path $Vault '.git\obsidian-log-commit-msg.txt'
    try {
        [System.IO.File]::WriteAllText($msgAbs, ("{0}`n" -f $subject), $Utf8NoBom)
        Invoke-Git @('-c', 'i18n.commitEncoding=UTF-8', 'commit', '-F', '.git/obsidian-log-commit-msg.txt') | Out-Null
    } finally {
        if (Test-Path -LiteralPath $msgAbs) { Remove-Item -LiteralPath $msgAbs -Force }
    }

    $sha = ((Invoke-Git @('rev-parse', '--short', 'HEAD')).Output | Out-String).Trim()
    $branch = ((Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')).Output | Out-String).Trim()
    Write-Output ('COMMITTED={0} {1}' -f $sha, $subject)

    # 4. リモートと突き合わせる
    $originResult = Invoke-Git @('remote', 'get-url', 'origin') -AllowFailure
    if ($originResult.ExitCode -ne 0) {
        Write-Output 'PUSH_SKIPPED: origin が未設定です。ensure-vault-repo.ps1 を実行してください。'
        exit 5
    }
    $originUrl = (($originResult.Output | Out-String).Trim())

    # オフラインを先に見切る。git の HTTP タイムアウトを待つと数十秒固まる。
    $remoteHost = 'github.com'
    if ($originUrl -match '^[a-z]+://([^/@]+@)?([^/:]+)') { $remoteHost = $Matches[2] }
    elseif ($originUrl -match '^[^@]+@([^:]+):') { $remoteHost = $Matches[1] }
    if (-not (Test-Reachable -HostName $remoteHost)) {
        Write-Output ('OFFLINE: {0} に到達できません。ノートとコミット {1} はローカルに残っています。' -f $remoteHost, $sha)
        Write-Output ('  次回の同期でまとめて上がります。手動なら: git -C "{0}" push origin {1}' -f $Vault, $branch)
        exit 5
    }

    $fetch = Invoke-Git @('fetch', 'origin') -AllowFailure
    if ($fetch.ExitCode -ne 0) {
        Write-Output ('PUSH_FAILED: fetch できませんでした（オフラインか認証切れ）。ノートとコミット {0} はローカルに残っています。' -f $sha)
        Write-Output ('  再試行: git -C "{0}" push origin {1}' -f $Vault, $branch)
        exit 5
    }

    $remoteRef = ('origin/{0}' -f $branch)
    $hasRemoteBranch = (Invoke-Git @('rev-parse', '--verify', $remoteRef) -AllowFailure).ExitCode -eq 0
    if ($hasRemoteBranch) {
        $behind = ((Invoke-Git @('rev-list', '--count', ('HEAD..{0}' -f $remoteRef))).Output | Out-String).Trim()
        if ([int]$behind -gt 0) {
            # ノートは 1 件 1 ファイルなので実質衝突しない。単一ユーザーが複数端末から
            # 書く用途なので、履歴を直線に保つため merge ではなく rebase を使う。
            $pull = Invoke-Git @('pull', '--rebase', 'origin', $branch) -AllowFailure
            if ($pull.ExitCode -ne 0) {
                Invoke-Git @('rebase', '--abort') -AllowFailure | Out-Null
                Write-Output ('REBASE_CONFLICT: リモートの {0} 件と衝突しました。rebase は中断済みで、コミット {1} はローカルに残っています。' -f $behind, $sha)
                Write-Output ('  手動で解消: git -C "{0}" pull --rebase origin {1}' -f $Vault, $branch)
                exit 4
            }
            Write-Output ('REBASED: リモートの {0} 件を取り込みました' -f $behind)
            $sha = ((Invoke-Git @('rev-parse', '--short', 'HEAD')).Output | Out-String).Trim()
        }
    }

    # 5. push
    $push = Invoke-Git @('push', '-u', 'origin', $branch) -AllowFailure
    if ($push.ExitCode -ne 0) {
        Write-Output ('PUSH_FAILED: push できませんでした。ノートとコミット {0} はローカルに残っています。' -f $sha)
        Write-Output ('  再試行: git -C "{0}" push origin {1}' -f $Vault, $branch)
        exit 5
    }

    Write-Output ('SYNCED: {0} {1} files -> {2}' -f $sha, $changed.Count, $branch)
    exit 0

} finally {
    Pop-Location
}
