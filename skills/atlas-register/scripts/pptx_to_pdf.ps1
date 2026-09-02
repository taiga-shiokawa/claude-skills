# pptx を PDF に変換する（preview.pdf の生成用）。
#
# 図鑑は pptx を自動変換しないため、preview が無い事例はサムネイルもビューアも出ず、
# 「Google Drive で開く」導線だけになる。preview.pdf を添えると詳細画面で全ページ読める。
# この環境には PowerPoint があるので COM 経由で変換できる。人に書き出しを頼む必要はない。
#
# 使い方:
#   powershell -File pptx_to_pdf.ps1 -Path "C:\path\to\deck.pptx" -Out "C:\path\to\preview.pdf"
#
# 注意: PowerPoint が未インストールの環境では失敗する。その場合はユーザーに
#       「PowerPoint の エクスポート → PDF/XPS」での書き出しを依頼する。

param(
  [Parameter(Mandatory = $true)][string]$Path,
  [Parameter(Mandatory = $true)][string]$Out
)

if (-not (Test-Path $Path)) {
  Write-Output "ERROR: file not found: $Path"
  exit 1
}

$key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\POWERPNT.EXE"
if (-not (Test-Path $key)) {
  Write-Output "ERROR: PowerPoint not installed. Ask the user to export the PDF manually."
  exit 1
}

# 相対パスだと PowerPoint COM が解決できないので絶対パスにする
$srcFull = (Resolve-Path $Path).Path
$outDir = Split-Path $Out -Parent
if ($outDir -and -not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Force $outDir | Out-Null
}
$outFull = [System.IO.Path]::GetFullPath($Out)

$pp = $null
$deck = $null
try {
  $pp = New-Object -ComObject PowerPoint.Application
  # Open(FileName, ReadOnly, Untitled, WithWindow)
  $deck = $pp.Presentations.Open($srcFull, $true, $false, $false)
  $deck.SaveAs($outFull, 32)   # 32 = ppSaveAsPDF
  Write-Output "SAVED: $outFull"
}
catch {
  Write-Output ("ERROR: " + $_.Exception.Message)
  exit 1
}
finally {
  if ($deck -ne $null) { try { $deck.Close() } catch {} }
  if ($pp -ne $null) { try { $pp.Quit() } catch {} }
}

if (Test-Path $outFull) {
  Write-Output ("SizeKB: " + [math]::Round((Get-Item $outFull).Length / 1KB, 1))
}
