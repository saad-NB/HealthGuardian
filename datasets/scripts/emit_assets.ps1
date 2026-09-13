# emit_assets.ps1
# Convert the normalized intermediate files into compact bundled app assets.
#   datasets/intermediate/drug_names.csv -> assets/data/drug_names.json
#   datasets/intermediate/ddi.csv        -> assets/data/ddi.json
#
# Severity is encoded as an index into ["reported","moderate","severe","contraindicated"].
# Usage: pwsh -File datasets/scripts/emit_assets.ps1

param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

$ErrorActionPreference = 'Stop'
$inter = Join-Path $Root 'datasets\intermediate'
$out   = Join-Path $Root 'assets\data'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$sevMap = @{ 'reported' = 0; 'moderate' = 1; 'severe' = 2; 'contraindicated' = 3 }
$enc = New-Object System.Text.UTF8Encoding($false)
function Esc([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }

$ddi = Import-Csv (Join-Path $inter 'ddi.csv')
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('{"version":"2026-09-12","severity":["reported","moderate","severe","contraindicated"],"pairs":[')
$first = $true
foreach ($r in $ddi) {
  $s = $sevMap[$r.severity]; if ($null -eq $s) { $s = 0 }
  if (-not $first) { [void]$sb.Append(',') }
  $first = $false
  [void]$sb.Append('["').Append((Esc $r.name_a)).Append('","').Append((Esc $r.name_b)).Append('",').Append($s).Append(']')
}
[void]$sb.Append(']}')
[System.IO.File]::WriteAllText((Join-Path $out 'ddi.json'), $sb.ToString(), $enc)
Write-Host ("ddi.json: {0} pairs" -f $ddi.Count)

$names = Import-Csv (Join-Path $inter 'drug_names.csv')
$sb2 = New-Object System.Text.StringBuilder
[void]$sb2.Append('{"version":"2026-09-12","names":[')
$first = $true
foreach ($r in $names) {
  if (-not $first) { [void]$sb2.Append(',') }
  $first = $false
  [void]$sb2.Append('["').Append((Esc $r.name)).Append('","').Append((Esc $r.rxcui)).Append('"]')
}
[void]$sb2.Append(']}')
[System.IO.File]::WriteAllText((Join-Path $out 'drug_names.json'), $sb2.ToString(), $enc)
Write-Host ("drug_names.json: {0} names" -f $names.Count)

Get-ChildItem $out | Select-Object Name, Length | Format-Table -AutoSize | Out-String -Width 120
