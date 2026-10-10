$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$tessdataDir = Join-Path $repoRoot 'assets\tessdata'
New-Item -ItemType Directory -Path $tessdataDir -Force | Out-Null

$models = @(
    @{ Name = 'kan.traineddata'; Url = 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/kan.traineddata' },
    @{ Name = 'eng.traineddata'; Url = 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/eng.traineddata' }
)

foreach ($model in $models) {
    $destination = Join-Path $tessdataDir $model.Name
    if ((Test-Path $destination) -and (Get-Item $destination).Length -gt 100000) {
        Write-Host "$($model.Name) already exists; keeping the downloaded model."
        continue
    }

    Write-Host "Downloading $($model.Name) (Tesseract fast model)..."
    Invoke-WebRequest -Uri $model.Url -OutFile $destination -UseBasicParsing
    if (!(Test-Path $destination) -or (Get-Item $destination).Length -le 100000) {
        Remove-Item $destination -Force -ErrorAction SilentlyContinue
        throw "Download failed or returned an invalid file for $($model.Name). Check your internet connection and rerun this script."
    }
    Write-Host "Downloaded $($model.Name): $([math]::Round((Get-Item $destination).Length / 1MB, 2)) MB"
}

Write-Host ''
Write-Host 'Kannada OCR models are ready. Now run: flutter pub get; flutter run'
