$content = Get-Content "D:\vibe-coding-portable-kit\vibe-coding-portable\docs\estensione\service\main.js" -Raw
$idx = $content.IndexOf("7200")
if($idx -ge 0) {
    $start = [Math]::Max(0, $idx - 400)
    $end = [Math]::Min($content.Length, $idx + 400)
    Write-Output $content.Substring($start, $end - $start)
}
