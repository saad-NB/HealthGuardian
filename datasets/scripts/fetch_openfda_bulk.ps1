# fetch_openfda_bulk.ps1
# Download the static openFDA drug/label bulk export (no API rate limits).
#
# The API is used ONLY to read the download manifest; the data itself comes from
# the static files under download.open.fda.gov. Downloads are resumable: partial
# files are kept as *.part and continued with curl -C -.
#
# Output:
#   datasets/intermediate/openfda_manifest.json   (tracked snapshot, provenance)
#   datasets/openfda/bulk/drug-label-*.json.zip   (gitignored, ~1.8 GB)
#
# Usage:
#   pwsh -File datasets/scripts/fetch_openfda_bulk.ps1
#   pwsh -File datasets/scripts/fetch_openfda_bulk.ps1 -MaxParts 1   # smoke test

param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [int]$MaxParts = 0,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$manifestUrl = 'https://api.fda.gov/download.json'
$interDir = Join-Path $Root 'intermediate'
$bulkDir = Join-Path $Root 'openfda\bulk'
New-Item -ItemType Directory -Force -Path $interDir, $bulkDir | Out-Null

$curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $curl) { throw 'curl.exe not found (required for resumable downloads).' }

Write-Host 'Fetching openFDA download manifest...'
$manifest = Invoke-RestMethod -Uri $manifestUrl -TimeoutSec 120 -Headers @{ 'User-Agent' = 'HealthGuardian-research' }
$label = $manifest.results.drug.label
if (-not $label) { throw 'Manifest has no results.drug.label section.' }

$snapshot = [pscustomobject]@{
  fetched_at = (Get-Date).ToUniversalTime().ToString('o')
  endpoint   = 'drug/label'
  export_date = $label.export_date
  total_records = $label.total_records
  partitions = $label.partitions
}
$snapshot | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $interDir 'openfda_manifest.json') -Encoding UTF8
Write-Host ("  export_date={0}  records={1}  parts={2}" -f $label.export_date, $label.total_records, $label.partitions.Count)

$parts = $label.partitions
if ($MaxParts -gt 0) { $parts = $parts | Select-Object -First $MaxParts }

$done = 0
foreach ($p in $parts) {
  $name = Split-Path $p.file -Leaf
  $dest = Join-Path $bulkDir $name
  $expected = [int64]([double]$p.size_mb * 1MB)
  if (-not $Force -and (Test-Path $dest)) {
    $actual = (Get-Item $dest).Length
    if ([Math]::Abs($actual - $expected) -lt 100KB) {
      Write-Host ("  [skip] {0} ({1:N0} bytes)" -f $name, $actual)
      $done++
      continue
    }
    Write-Host ("  [redo] {0} size mismatch ({1:N0} vs ~{2:N0})" -f $name, $actual, $expected)
    Remove-Item -Force $dest
  }

  $part = "$dest.part"
  $curlArgs = @('-L', '--fail', '--show-error', '--retry', '5', '--retry-delay', '5', '-o', $part)
  if (Test-Path $part) { $curlArgs += @('-C', '-') }
  $curlArgs += $p.file

  Write-Host ("  [get ] {0} ({1} MB)" -f $name, $p.size_mb)
  & $curl @curlArgs
  if ($LASTEXITCODE -ne 0) { throw "curl failed for $($p.file) (exit $LASTEXITCODE)" }
  Move-Item -Force $part $dest
  $done++
}

Write-Host ("DONE. {0}/{1} parts present in {2}" -f $done, @($label.partitions).Count, $bulkDir)
