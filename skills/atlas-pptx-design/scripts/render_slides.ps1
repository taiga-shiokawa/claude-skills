# PowerPoint COM で全スライドを PNG に書き出す（視覚QA用）。
# 使い方: powershell -File render_slides.ps1 -Pptx <入力.pptx> -OutDir <出力先> [-Width 1600]
# PowerPoint 本体が必要。対象ファイルを PowerPoint で開いたまま実行しないこと。
param(
    [Parameter(Mandatory = $true)][string]$Pptx,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$Width = 1600
)
$ErrorActionPreference = "Stop"
$pptxPath = (Resolve-Path $Pptx).Path
New-Item -ItemType Directory -Force $OutDir | Out-Null
$outPath = (Resolve-Path $OutDir).Path
Get-ChildItem $outPath -Filter "slide-*.png" | Remove-Item -Force

$app = New-Object -ComObject PowerPoint.Application
try {
    # Open(path, ReadOnly, Untitled, WithWindow)
    $pres = $app.Presentations.Open($pptxPath, $true, $false, $false)
    $height = [int]($Width * $pres.PageSetup.SlideHeight / $pres.PageSetup.SlideWidth)
    $i = 1
    foreach ($slide in $pres.Slides) {
        $file = Join-Path $outPath ("slide-{0:d2}.png" -f $i)
        $slide.Export($file, "PNG", $Width, $height)
        $i++
    }
    $pres.Close()
    Write-Output "Exported $($i - 1) slides to $outPath"
}
finally {
    $app.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) | Out-Null
}
