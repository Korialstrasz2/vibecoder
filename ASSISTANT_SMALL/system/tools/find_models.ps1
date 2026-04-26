# find_models.ps1
# Finds Gemma GGUF models in GEMMA_4_SMALL and GEMMA_4_LAAARGE folders
# Writes results to temp files for batch script to consume

param(
    [Parameter(Mandatory=$true)]
    [string]$RootDir
)

$smallDir = Join-Path $RootDir "models\GEMMA_4_SMALL"
$largeDir = Join-Path $RootDir "models\GEMMA_4_LAAARGE"

# Find small model
$smallModel = ""
if (Test-Path $smallDir) {
    $files = Get-ChildItem -Path $smallDir -Filter "*.gguf" -File |
             Where-Object { $_.Name -match "gemma.*E2B" -or $_.Name -match "gemma.*small" -or $_.Name -match "gemma" } |
             Sort-Object Name
    if ($files.Count -gt 0) {
        $smallModel = $files[0].FullName
    }
}

# Find large model
$largeModel = ""
if (Test-Path $largeDir) {
    $files = Get-ChildItem -Path $largeDir -Filter "*.gguf" -File |
             Where-Object { $_.Name -match "gemma.*E4B" -or $_.Name -match "gemma.*large" -or $_.Name -match "gemma" } |
             Sort-Object Name
    if ($files.Count -gt 0) {
        $largeModel = $files[0].FullName
    }
}

# Write to temp files for batch script to read
$tempSmall = "$env:TEMP\gemma_small.txt"
$tempLarge = "$env:TEMP\gemma_large.txt"

# Only write if we found something
if ($smallModel -ne "") {
    $smallModel | Out-File -FilePath $tempSmall -Encoding ASCII -NoNewline
} else {
    Remove-Item $tempSmall -ErrorAction SilentlyContinue
}

if ($largeModel -ne "") {
    $largeModel | Out-File -FilePath $tempLarge -Encoding ASCII -NoNewline
} else {
    Remove-Item $tempLarge -ErrorAction SilentlyContinue
}
