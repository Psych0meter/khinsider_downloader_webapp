param (
    [Parameter(Mandatory = $true)]
    [string]$albumUrl
)

# Set User-Agent to avoid blocking
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

# Start timer
$startTime = Get-Date

# Fetch album page
Write-Host "Fetching album page: $albumUrl"
$albumPage = Invoke-WebRequest -Uri $albumUrl -Headers @{"User-Agent" = $userAgent} -UseBasicParsing

# Extract album title
if ($albumPage.Content -match "<title>(.*?) - Download") {
    $albumTitle = $matches[1].Trim()
} else {
    $albumTitle = "Unknown_Album"
}

# Remove invalid characters from the album name
$albumTitle = $albumTitle -replace "[^\w\s-]", ""

# Define album folder
$downloadPath = Join-Path $PSScriptRoot $albumTitle
if (!(Test-Path $downloadPath)) { 
    New-Item -ItemType Directory -Path $downloadPath | Out-Null
    Write-Host "Created album folder: $downloadPath"
} else {
    Write-Host "Using existing album folder: $downloadPath"
}

# Extract all song page links (avoiding duplicates)
$songPageLinks = $albumPage.Links | Where-Object { $_.href -match "/game-soundtracks/album/[^?]+\.mp3$" } | Select-Object -ExpandProperty href | Sort-Object -Unique

if ($songPageLinks.Count -eq 0) {
    Write-Host "No songs found! Check the URL."
    exit
}

Write-Host "Found $($songPageLinks.Count) unique song pages. Extracting download links..."

# Store all unique download links (keyed by base name)
$downloadLinks = @{}

foreach ($songLink in $songPageLinks) {
    $songPageUrl = "https://downloads.khinsider.com$($songLink)"

    Write-Host "Processing: $songPageUrl"
    $songPage = Invoke-WebRequest -Uri $songPageUrl -Headers @{"User-Agent" = $userAgent} -UseBasicParsing

    # Extract FLAC, MP3, and M4A download links
    $fileLinks = $songPage.Links | Where-Object { $_.href -match "https://.*\.(flac|mp3|m4a)$" } | Select-Object -ExpandProperty href

    foreach ($fileUrl in $fileLinks) {
        $fileName = [System.Uri]::UnescapeDataString(($fileUrl.Split("/")[-1]))
        $fileName = $fileName -replace "[\[\]]", "_"  # Replace '[' and ']' with '_'

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $ext = [System.IO.Path]::GetExtension($fileName)

        if ($downloadLinks.ContainsKey($baseName)) {
            # Prefer FLAC over MP3/M4A
            if ($ext -eq ".flac" -and $downloadLinks[$baseName].Extension -ne ".flac") {
                $downloadLinks[$baseName] = [PSCustomObject]@{ Url = $fileUrl; Extension = $ext }
            }
        } else {
            $downloadLinks[$baseName] = [PSCustomObject]@{ Url = $fileUrl; Extension = $ext }
        }
    }
}

Write-Host "Total unique files to download: $($downloadLinks.Count)"

# Download each unique file and track total size
$totalSize = 0
$filesDownloaded = 0

foreach ($baseName in $downloadLinks.Keys) {
    $fileUrl = $downloadLinks[$baseName].Url
    $ext = $downloadLinks[$baseName].Extension
    $fileName = "$baseName$ext"
    $filePath = Join-Path $downloadPath $fileName

    Write-Host "Downloading: $fileUrl -> $filePath"
    Invoke-WebRequest -Uri $fileUrl -OutFile $filePath -Headers @{"User-Agent" = $userAgent}

    if (Test-Path $filePath) {
        $fileSize = (Get-Item $filePath).Length
        $totalSize += $fileSize
        $filesDownloaded++
    }
}

# End timer
$endTime = Get-Date
$timeTaken = $endTime - $startTime

# Convert total size to human-readable format
function Convert-Size ($size) {
    if ($size -ge 1GB) { return "{0:N2} GB" -f ($size / 1GB) }
    elseif ($size -ge 1MB) { return "{0:N2} MB" -f ($size / 1MB) }
    elseif ($size -ge 1KB) { return "{0:N2} KB" -f ($size / 1KB) }
    else { return "$size Bytes" }
}

$totalSizeFormatted = Convert-Size $totalSize

# Final Summary
Write-Host "`n=== DOWNLOAD SUMMARY ==="
Write-Host "Album: $albumTitle"
Write-Host "Total Files Downloaded: $filesDownloaded"
Write-Host "Total Size: $totalSizeFormatted"
Write-Host "Time Taken: $($timeTaken.Minutes) min $($timeTaken.Seconds) sec"
Write-Host "Files saved in: $downloadPath"
