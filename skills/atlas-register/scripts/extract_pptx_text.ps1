# pptx の全スライドからテキストを抽出する。
#
# pptx は zip なので、各 slideN.xml の <a:t> タグを拾えば読める。
# Drive へ上げる前に内容を把握できるので、起案の提示とアップロード依頼を1往復にまとめられる。
#
# 実装メモ:
#   - 展開せず ZipFile で直接読む。Expand-Archive を %TEMP% へ使う実装は、
#     ユーザー名に日本語が含まれる環境で展開が空振りしスライド0件になった。
#   - パイプラインを継続行（行末 |）で書くと、この環境では抽出が1件に化けた。
#     Where と Sort を変数に分けた下記の形は実績がある。崩さないこと。
#
# 使い方:
#   powershell -File extract_pptx_text.ps1 -Path "C:\path\to\deck.pptx"
#   powershell -File extract_pptx_text.ps1 -Path "..." -MaxCharsPerSlide 1200

param(
  [Parameter(Mandatory = $true)][string]$Path,
  [int]$MaxCharsPerSlide = 700
)

if (-not (Test-Path $Path)) {
  Write-Output "ERROR: file not found: $Path"
  exit 1
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$srcFull = (Resolve-Path $Path).Path
$zip = $null

try {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($srcFull)
  $matched = $zip.Entries | Where-Object { $_.FullName -match '^ppt/slides/slide[0-9]+\.xml$' }
  $slides = $matched | Sort-Object { [int]($_.Name -replace '\D', '') }
  Write-Output ("SLIDE_COUNT: " + @($slides).Count)

  foreach ($entry in $slides) {
    $reader = New-Object System.IO.StreamReader($entry.Open())
    try { $xml = $reader.ReadToEnd() } finally { $reader.Close() }
    $texts = [regex]::Matches($xml, '<a:t>(.*?)</a:t>') | ForEach-Object { $_.Groups[1].Value }
    $joined = ($texts -join ' | ')
    if ($joined.Length -gt $MaxCharsPerSlide) {
      $joined = $joined.Substring(0, $MaxCharsPerSlide) + ' ...'
    }
    Write-Output ("--- " + [System.IO.Path]::GetFileNameWithoutExtension($entry.Name) + " ---")
    Write-Output $joined
  }
}
catch {
  Write-Output ("ERROR: " + $_.Exception.Message)
  exit 1
}
finally {
  if ($zip -ne $null) { $zip.Dispose() }
}
