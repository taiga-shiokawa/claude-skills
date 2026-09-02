<#
  read-session.ps1 — Claude Code のセッション JSONL から user / assistant の本文だけを抜き出す。

  JSONL には tool_use / tool_result が大量に混ざっていて、そのまま読むとコンテキストが
  一瞬で埋まる。ここでは本文テキストだけを拾い、1発言あたりの長さも切り詰める。

  使い方:
    # いまのセッションの ID とファイルパスだけ知りたい（frontmatter の session 用）
    powershell -File read-session.ps1 -InfoOnly

    # いまのセッションの本文を読む（直近 60 発言）
    powershell -File read-session.ps1 -Tail 60

    # 別のプロジェクト / 特定のファイルを読む
    powershell -File read-session.ps1 -Cwd "C:\path\to\project"
    powershell -File read-session.ps1 -Path "C:\...\<session-id>.jsonl"
#>
[CmdletBinding()]
param(
  # 読む JSONL。省略時は -Cwd から自動解決する
  [string]$Path,
  # セッションを探す基準ディレクトリ（既定はカレント）
  [string]$Cwd = (Get-Location).Path,
  # 1発言あたりの最大文字数
  [int]$MaxChars = 1200,
  # 末尾から何発言ぶん出すか（0 = 全部）
  [int]$Tail = 0,
  # ヘッダ（セッション ID とパス）だけ出して終わる
  [switch]$InfoOnly
)

$ErrorActionPreference = 'Stop'

function Get-ProjectSlug([string]$p) {
  # Claude Code は cwd の英数字以外をすべて '-' に置換したものをフォルダ名にする。
  # 日本語 1 文字も '-' 1 個になる（例: GOOYAラウンダー6 -> GOOYA-----6）。
  -join ($p.ToCharArray() | ForEach-Object { if ($_ -match '[A-Za-z0-9]') { $_ } else { '-' } })
}

if (-not $Path) {
  $slug = Get-ProjectSlug $Cwd
  $dir  = Join-Path $env:USERPROFILE ".claude\projects\$slug"
  if (-not (Test-Path -LiteralPath $dir)) {
    Write-Error "セッションディレクトリが無い: $dir`n（-Cwd がそのセッションの作業ディレクトリか確認する）"
    exit 1
  }
  $newest = Get-ChildItem -LiteralPath $dir -Filter *.jsonl |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $newest) { Write-Error "JSONL が無い: $dir"; exit 1 }
  $Path = $newest.FullName
}

if (-not (Test-Path -LiteralPath $Path)) { Write-Error "ファイルが無い: $Path"; exit 1 }

$sessionId = [System.IO.Path]::GetFileNameWithoutExtension($Path)
Write-Output "SESSION_FILE : $Path"
Write-Output "SESSION_ID   : $sessionId"
Write-Output ("SESSION_SHORT: " + $sessionId.Substring(0, [Math]::Min(8, $sessionId.Length)))
if ($InfoOnly) { return }
Write-Output ""

$messages = New-Object System.Collections.ArrayList

foreach ($line in [System.IO.File]::ReadLines($Path, [System.Text.Encoding]::UTF8)) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  try { $o = $line | ConvertFrom-Json } catch { continue }

  if ($o.type -ne 'user' -and $o.type -ne 'assistant') { continue }
  if ($o.isSidechain) { continue }   # サブエージェント側の会話は除く
  if ($o.isMeta) { continue }

  $content = $o.message.content
  if ($null -eq $content) { continue }

  $texts = @()
  if ($content -is [string]) {
    $texts += $content
  } else {
    foreach ($b in $content) {
      if ($b.type -eq 'text' -and $b.text) { $texts += $b.text }
    }
  }

  foreach ($t in $texts) {
    # ツール結果・system-reminder・コマンド展開はノイズなので落とす
    $t = [regex]::Replace($t, '(?s)<system-reminder>.*?</system-reminder>', '')
    $t = [regex]::Replace($t, '(?s)<local-command-stdout>.*?</local-command-stdout>', '')
    $t = $t.Trim()
    if ($t.Length -eq 0) { continue }
    if ($t.Length -gt $MaxChars) { $t = $t.Substring(0, $MaxChars) + " …（以下略）" }
    [void]$messages.Add([pscustomobject]@{ Role = $o.type; Text = $t })
  }
}

$out = if ($Tail -gt 0 -and $messages.Count -gt $Tail) { $messages[($messages.Count - $Tail)..($messages.Count - 1)] } else { $messages }

Write-Output "MESSAGES: $($out.Count) / $($messages.Count)"
Write-Output ""
foreach ($m in $out) {
  Write-Output "--- $($m.Role) ---"
  Write-Output $m.Text
  Write-Output ""
}
