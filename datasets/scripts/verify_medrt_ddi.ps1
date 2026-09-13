# verify_medrt_ddi.ps1
# Hard gate: confirm whether MED-RT carries DDI pair relations with severity.
# Result (2026-09-12): NO. Accessory files are NDFRT<->MeSH and NDFRT<->RxNorm
# crosswalks only; the DTS ontology has no `severity`/`has_DDI`. The pipeline
# therefore uses the frozen 2018 NDF-RT for pairs and MED-RT for classes only.
#
# Usage: pwsh -File datasets/scripts/verify_medrt_ddi.ps1

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$outDir = Join-Path $PSScriptRoot '..\med-rt'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host 'Downloading MED-RT accessory + DTS bundles...'
Invoke-WebRequest -Uri 'https://evs.nci.nih.gov/ftp1/MED-RT/Core_MEDRT_Accessory_Files.zip' `
  -OutFile (Join-Path $outDir 'Core_MEDRT_Accessory_Files.zip') -TimeoutSec 120
Invoke-WebRequest -Uri 'https://evs.nci.nih.gov/ftp1/MED-RT/Core_MEDRT_DTS.zip' `
  -OutFile (Join-Path $outDir 'Core_MEDRT_DTS.zip') -TimeoutSec 120

Add-Type -AssemblyName System.IO.Compression.FileSystem

Write-Host "`nAccessory files (expect crosswalks only):"
$z = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path (Join-Path $outDir 'Core_MEDRT_Accessory_Files.zip')))
$z.Entries | ForEach-Object { "  $($_.FullName)  ($($_.Length))" }
$z.Dispose()

Write-Host "`nScanning DTS ontology for DDI signals..."
$dts = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path (Join-Path $outDir 'Core_MEDRT_DTS.zip')))
$entry = $dts.Entries | Where-Object { $_.FullName -like '*_DTS.xml' } | Select-Object -First 1
$extract = Join-Path $outDir 'MEDRT_DTS.xml'
[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $extract, $true)
$dts.Dispose()

$content = Get-Content -Raw $extract
foreach ($term in @('has_DDI', 'severity', 'Severity')) {
  $n = ([regex]::Matches($content, [regex]::Escape($term))).Count
  Write-Host ("  {0} : {1}" -f $term, $n)
}

Write-Host "`nVerdict: if has_DDI/severity counts are 0, MED-RT has no graded DDI table."
Write-Host "Pipeline: use frozen 2018 NDF-RT (datasets/ndf-rt) for pairs; MED-RT for classes."
