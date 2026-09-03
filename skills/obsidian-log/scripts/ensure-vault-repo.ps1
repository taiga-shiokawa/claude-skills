<#
.SYNOPSIS
    Obsidian 保管庫を GitHub Private リポジトリの作業ツリーとして初期化する。

.DESCRIPTION
    冪等。何度実行しても、既にある物には触らない。
    obsidian-log スキルの「手順5 — GitHub へ同期」が前提とする状態を、一度だけ整えるためのもの。

    GitHub にリポジトリを作るのは外向きの一回限りの操作なので、毎回走る sync-vault.ps1 とは
    別スクリプトに分けてある。sync 側はこのスクリプトの実行を促すだけで、自分では作らない。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File ensure-vault-repo.ps1 -DryRun
    powershell -NoProfile -ExecutionPolicy Bypass -File ensure-vault-repo.ps1

.NOTES
    このファイルは UTF-8 BOM 付きで保存する。Windows PowerShell 5.1 は BOM の無いファイルを
    ANSI として読むため、BOM を落とすと日本語がすべて壊れてパースエラーになる。
#>
[CmdletBinding()]
param(
    # 保管庫のパス。PC 交換でユーザー名が変わっても追随するよう %USERPROFILE% から組み立てる。
    [string]$Vault = (Join-Path $env:USERPROFILE 'Documents\AI Log'),

    # GitHub 上のリポジトリ。owner を含むフルネームで指定する（既定 owner に任せると
    # 組織側に作られる余地があるため）。
    [string]$Repo = 'taiga-shiokawa/obsidian-ai-log',

    # 何も変更せず、やろうとしていることだけ出す。
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# git が返す日本語パスを壊さないため、入出力とも UTF-8 に寄せる。
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# git 用の設定ファイルは BOM なしで書く。.gitignore に BOM が付くと先頭行のパターンが
# マッチしなくなり、除外したはずの物が追跡される。
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 対話プロンプトで固まらせない。認証切れのときに Git Credential Manager の GUI が出ると、
# スキルが無反応のまま待ち続ける。即失敗させて報告に回す。
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'never'

function Write-Step {
    param([string]$State, [string]$Message)
    Write-Output ('[{0,-7}] {1}' -f $State, $Message)
}

function Invoke-Git {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $out = & git @Arguments
    $code = $LASTEXITCODE
    if (($code -ne 0) -and (-not $AllowFailure)) {
        throw ("git {0} が失敗しました (exit {1})`n{2}" -f ($Arguments -join ' '), $code, ($out -join "`n"))
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $out }
}

function Write-FileIfAbsent {
    param([string]$Path, [string]$Content, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Write-Step 'SKIP' ("{0} は既にあるので触らない" -f $Label)
        return $false
    }
    if ($DryRun) {
        Write-Step 'DRYRUN' ("{0} を作成する" -f $Label)
        return $false
    }
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
    Write-Step 'CREATE' ("{0} を作成した" -f $Label)
    return $true
}

# ---------------------------------------------------------------------------
# 保管庫に置くファイルの中身
# ---------------------------------------------------------------------------

$GitIgnoreBody = @'
# 保管庫内にネストした別リポジトリ（taiga-shiokawa/codex-skills のクローン）。
# git add すると壊れた gitlink になり、中身が実質バックアップされない事故になるため除外する。
# 必要になったら保管庫内で個別に clone する。
codex-skills/

# 開いているタブ・ペイン構成。ノートを書くたびに書き換わり毎回 diff が出るため追跡しない。
.obsidian/workspace.json
.obsidian/workspace-mobile.json

# Obsidian のローカルキャッシュと削除待ち。端末固有で復元価値が無い。
.obsidian/cache
.trash/

# コミュニティプラグインとテーマの本体。入れ直せるコードで容量も大きい。
# 「どれを入れていたか」は community-plugins.json 側に残るので復元はできる。
.obsidian/plugins/
.obsidian/themes/

# Windows / エディタが撒くゴミ
Thumbs.db
desktop.ini
.DS_Store
.vscode/
.idea/
*.swp

# 下書きや退避ファイルを保管庫に置いたまま巻き込む事故を防ぐ。
*.tmp
*.bak
~$*

# 注意: .obsidian/app.json / appearance.json / core-plugins.json / graph.json は
# 意図的に追跡している。新しいPCでプラグイン構成とグラフ設定をそのまま復元するため。
'@

$GitAttributesBody = @'
# 改行を LF に固定する。core.autocrlf は Git for Windows の system config 由来で
# 端末ごとに違い得るため、リポジトリ側で決めて「全行変更」の偽 diff を防ぐ。
# 保管庫のノートは Write ツールが LF で書くので、LF に寄せるのが実態に合う。
* text=auto eol=lf

# 将来ノートに画像や PDF を添付したとき、改行変換で壊されないようにしておく。
*.png  binary
*.jpg  binary
*.jpeg binary
*.gif  binary
*.webp binary
*.pdf  binary
'@

$ReadmeBody = @'
# AI Log

AI コーディングツール（Claude Code / Codex）との作業ログを残す Obsidian 保管庫。
このリポジトリ自体が保管庫のルートで、`.md` を置けば Obsidian に反映される。

ノートは `obsidian-log` スキルが書く。会話ログの全文ではなく「後から検索して役に立つ要点」だけを
1セッション1枚に再構成したもの。全文は各ツールのセッション履歴に残っている。

## ノートの形

ファイル名は `YYYY-MM-DD` + 全角スペース + 日本語タイトル。frontmatter の `date` / `project` /
`session` / `tags` で検索する。`tags` の先頭は必ず発生源（`claude-code` または `codex`）。

## 追跡していないもの

| 対象 | 理由 |
| --- | --- |
| `codex-skills/` | 保管庫内にネストした別リポジトリ（taiga-shiokawa/codex-skills）のクローン。add すると壊れた gitlink になる |
| `.obsidian/workspace.json` | 開いているタブ構成。ノートを書くたびに書き換わる |
| `.obsidian/cache`, `.trash/` | 端末固有で復元価値が無い |

`.obsidian` の残り（`app.json` / `appearance.json` / `core-plugins.json` / `graph.json`）は
意図的に追跡している。新しいPCでプラグイン構成とグラフ設定がそのまま戻る。

## 新しいPCで復元する

```powershell
gh auth login
gh repo clone taiga-shiokawa/obsidian-ai-log "$env:USERPROFILE\Documents\AI Log"
```

そのあと Obsidian で「フォルダを保管庫として開く」からこのフォルダを開く。
`codex-skills` が必要なら保管庫内で別途 clone する（`.gitignore` 済みなので追跡されない）。
スキル本体は別リポジトリ taiga-shiokawa/claude-skills から `~/.claude/` へコピーする。

## 秘密情報

このリポジトリに API キー・トークン・パスワード・接続文字列・第三者の個人情報は置かない。
要約であっても値は書かず、キー名だけにする（例: `OPENAI_API_KEY` を設定した）。
Private でも一度 push した秘密は履歴に残り続けるため、`sync-vault.ps1` が push 前に
正規表現スキャンをかけて検出したら commit せずに止める。
'@

# ---------------------------------------------------------------------------
# 手順
# ---------------------------------------------------------------------------

Write-Output '=== ensure-vault-repo ==='
if ($DryRun) { Write-Output '(DryRun: 何も変更しない)' }

# 1. 保管庫の存在確認
if (-not (Test-Path -LiteralPath $Vault -PathType Container)) {
    throw ("保管庫が見つかりません: {0}`n新しいPCなら、まず README の復元手順で clone してください。" -f $Vault)
}
Write-Step 'OK' ("保管庫: {0}" -f $Vault)

# 2. git / gh の前提確認
& git --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'git が見つかりません。' }

$RepoOwner = $Repo.Split('/')[0]
$ghLogin = & gh api user --jq '.login'
if ($LASTEXITCODE -ne 0) {
    throw "gh が未認証です。`ngh auth login を実行してから再試行してください。"
}
$ghLogin = ($ghLogin | Out-String).Trim()
if ($ghLogin -ne $RepoOwner) {
    throw ("gh のログインアカウント ({0}) が対象リポジトリの owner ({1}) と一致しません。`n個人アカウントで push する意図なので、gh auth switch などで切り替えてください。" -f $ghLogin, $RepoOwner)
}
Write-Step 'OK' ("gh アカウント: {0}（{1} の owner と一致）" -f $ghLogin, $Repo)

# 以降 git / gh は保管庫を作業ディレクトリにして実行する。
# 非ASCII なユーザー名を含むパスをネイティブ exe の引数に渡すのを避けるため、
# -C ではなく Push-Location を使う。
Push-Location -LiteralPath $Vault
try {

    # 3. リポジトリ初期化
    if (Test-Path -LiteralPath (Join-Path $Vault '.git')) {
        Write-Step 'SKIP' '既に git リポジトリ'
    } elseif ($DryRun) {
        Write-Step 'DRYRUN' 'git init -b main を実行する'
    } else {
        # -b main は必須。init.defaultBranch が未設定だと master になり、gh 既定の main とずれる。
        Invoke-Git @('init', '-b', 'main') | Out-Null
        Write-Step 'CREATE' 'git init -b main を実行した'
    }

    if ((-not (Test-Path -LiteralPath (Join-Path $Vault '.git'))) -and $DryRun) {
        Write-Output ''
        Write-Output '(DryRun: 未初期化のため以降の手順は判定のみ)'
    }

    # 4. 全角スペース入りのファイル名を 8 進エスケープせず表示させる
    if (Test-Path -LiteralPath (Join-Path $Vault '.git')) {
        $qp = Invoke-Git @('config', '--get', 'core.quotepath') -AllowFailure
        $qpVal = (($qp.Output | Out-String).Trim())
        if ($qpVal -eq 'false') {
            Write-Step 'SKIP' 'core.quotepath は既に false'
        } elseif ($DryRun) {
            Write-Step 'DRYRUN' 'core.quotepath=false を設定する'
        } else {
            Invoke-Git @('config', 'core.quotepath', 'false') | Out-Null
            Invoke-Git @('config', 'i18n.commitEncoding', 'utf-8') | Out-Null
            Invoke-Git @('config', 'i18n.logOutputEncoding', 'utf-8') | Out-Null
            Write-Step 'CREATE' 'core.quotepath=false と i18n.* を設定した（全角スペース入りのファイル名・日本語コミットメッセージ対策）'
        }
    }

    # 5. 保管庫のメタファイル（既存は絶対に上書きしない）
    Write-FileIfAbsent -Path (Join-Path $Vault '.gitignore')     -Content $GitIgnoreBody     -Label '.gitignore'     | Out-Null
    Write-FileIfAbsent -Path (Join-Path $Vault '.gitattributes') -Content $GitAttributesBody -Label '.gitattributes' | Out-Null
    Write-FileIfAbsent -Path (Join-Path $Vault 'README.md')      -Content $ReadmeBody        -Label 'README.md'      | Out-Null

    if ($DryRun) {
        Write-Output ''
        Write-Output 'DryRun 終了。実行するには -DryRun を外してください。'
        return
    }

    # 6. codex-skills が追跡されていないことを確認（壊れた gitlink を作らせない）
    $tracked = Invoke-Git @('ls-files', '--error-unmatch', 'codex-skills') -AllowFailure
    if ($tracked.ExitCode -eq 0) {
        throw "codex-skills が追跡されています。壊れた gitlink になっているため、`ngit rm --cached -r codex-skills`nで外してから再試行してください。"
    }
    Write-Step 'OK' 'codex-skills は追跡されていない'

    # 7. 初回コミット
    $status = Invoke-Git @('status', '--porcelain')
    $hasChanges = (($status.Output | Out-String).Trim().Length -gt 0)
    $hasHead = (Invoke-Git @('rev-parse', '--verify', 'HEAD') -AllowFailure).ExitCode -eq 0

    if (-not $hasChanges) {
        Write-Step 'SKIP' 'コミットする変更が無い'
    } else {
        # .gitignore に加えて pathspec でも codex-skills を外す。初回の add がいちばん危険で、
        # 一度 gitlink として index に入ると後から .gitignore を足しても外れない。
        Invoke-Git @('add', '-A', '--', '.', ':(exclude)codex-skills') | Out-Null
        if ($hasHead) {
            $msg = '保管庫の未コミット分をまとめて取り込む'
        } else {
            $msg = '保管庫を git 管理下に置く'
        }
        # 日本語のコミットメッセージは -m で渡さない。PS 5.1 はネイティブ exe への引数を
        # ANSI コードページで渡す経路があり化ける。UTF-8 のファイルに書いて -F で渡す。
        # 置き場所は .git 配下（追跡されない）にし、git へは相対の ASCII パスで渡す。
        $msgAbs = Join-Path $Vault '.git\obsidian-log-commit-msg.txt'
        try {
            [System.IO.File]::WriteAllText($msgAbs, ("chore: {0}`n" -f $msg), $Utf8NoBom)
            Invoke-Git @('-c', 'i18n.commitEncoding=UTF-8', 'commit', '-F', '.git/obsidian-log-commit-msg.txt') | Out-Null
        } finally {
            if (Test-Path -LiteralPath $msgAbs) { Remove-Item -LiteralPath $msgAbs -Force }
        }
        Write-Step 'CREATE' ('コミットした: chore: {0}' -f $msg)
    }

    $branch = ((Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')).Output | Out-String).Trim()

    # 8. リモートの用意
    $remote = Invoke-Git @('remote', 'get-url', 'origin') -AllowFailure
    if ($remote.ExitCode -eq 0) {
        Write-Step 'SKIP' ('origin は既にある: {0}' -f (($remote.Output | Out-String).Trim()))
        $push = Invoke-Git @('push', '-u', 'origin', $branch) -AllowFailure
        if ($push.ExitCode -eq 0) {
            Write-Step 'OK' ('push した ({0})' -f $branch)
        } else {
            Write-Step 'WARN' ('push に失敗した。ローカルコミットは残っている: git push -u origin {0}' -f $branch)
        }
    } else {
        $view = & gh repo view $Repo --json name
        if ($LASTEXITCODE -eq 0) {
            Invoke-Git @('remote', 'add', 'origin', ('https://github.com/{0}.git' -f $Repo)) | Out-Null
            Write-Step 'CREATE' ('origin を追加した（{0} は既に GitHub 上にある）' -f $Repo)
            Invoke-Git @('push', '-u', 'origin', $branch) | Out-Null
            Write-Step 'OK' ('push した ({0})' -f $branch)
        } else {
            & gh repo create $Repo --private --source . --remote origin --push
            if ($LASTEXITCODE -ne 0) { throw ('gh repo create {0} が失敗しました。' -f $Repo) }
            Write-Step 'CREATE' ('{0} を Private で作成し push した' -f $Repo)
        }
    }

    # 9. 結果
    $trackedCount = (Invoke-Git @('ls-files')).Output.Count
    Write-Output ''
    Write-Output ('VAULT={0}' -f $Vault)
    Write-Output ('REPO={0}' -f $Repo)
    Write-Output ('BRANCH={0}' -f $branch)
    Write-Output ('TRACKED_FILES={0}' -f $trackedCount)
    Write-Output 'READY: sync-vault.ps1 を使えます'

} finally {
    Pop-Location
}
