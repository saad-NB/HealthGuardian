# build_ddi.ps1
# Deterministic merge: NDF-RT pairs + ONC contraindicated list + NDFRT->RxNorm names.
# Outputs (tracked, in datasets/intermediate/):
#   drug_names.csv : rxcui,name,source        (autocomplete source)
#   ddi.csv        : name_a,name_b,severity,rxcui_a,rxcui_b,sources
#
# Severity model (public-domain sources only):
#   contraindicated <- present in ONC high-priority list
#   severe/moderate <- openFDA label context (enrichment overlay, enrich-only)
#   reported        <- NDF-RT pair with no ONC match and no openFDA grade
#   (openFDA enrichment is produced by mine_openfda.py from the bulk export)
#
# Usage: pwsh -File datasets/scripts/build_ddi.ps1
#        pwsh -File datasets/scripts/build_ddi.ps1 -SkipEnrich

param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$Enrich = '',
  [switch]$SkipEnrich
)

$ErrorActionPreference = 'Stop'

$ndf     = Join-Path $Root 'ndf-rt\NDF-RT-interactions.csv'
$mapFile = Join-Path $Root 'ndf-rt\NDFRT_RxNorm_mapping.csv'
$oncFile = Join-Path $Root 'onc\ONC_High_Priority_Mapped.csv'
$outDir  = Join-Path $Root 'intermediate'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$ti = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo

function Get-DisplayName([string]$s) {
  if (-not $s) { return '' }
  $s = $s -replace '\s*\[[^\]]*\]\s*', ' '
  $s = ($s -replace '\s+', ' ').Trim().ToLowerInvariant()
  return $ti.ToTitleCase($s)
}

function Get-NormKey([string]$s) {
  if (-not $s) { return '' }
  $s = $s -replace '\s*\[[^\]]*\]\s*', ' '
  $s = $s.ToUpperInvariant() -replace '[^A-Z0-9]+', ' '
  return ($s -replace '\s+', ' ').Trim()
}

function Get-PairKey([string]$a, [string]$b) {
  if ($a -le $b) { return "$a|$b" } else { return "$b|$a" }
}

Write-Host 'Loading NDFRT->RxNorm name map...'
$map = Import-Csv $mapFile -Delimiter ';'
$nameByRxcui = @{}
foreach ($m in $map) {
  $rx = ($m.rxcui).Trim()
  if (-not $rx) { continue }
  $display = Get-DisplayName $m.drugname
  if (-not $display) { continue }
  if (-not $nameByRxcui.ContainsKey($rx)) {
    $nameByRxcui[$rx] = $display
  } elseif ($m.drugname -notmatch '\[Chemical/Ingredient\]') {
    $nameByRxcui[$rx] = $display
  }
}
Write-Host ("  rxcui->name: {0}" -f $nameByRxcui.Count)

Write-Host 'Loading ONC high-priority pairs...'
$oncPairs = New-Object System.Collections.Generic.HashSet[string]
$oncNames = New-Object System.Collections.Generic.HashSet[string]
foreach ($line in (Get-Content $oncFile)) {
  $parts = $line.Split('$')
  if ($parts.Count -lt 4) { continue }
  $a = $parts[0].Trim(); $b = $parts[2].Trim()
  if (-not $a -or -not $b) { continue }
  $na = Get-NormKey $a; $nb = Get-NormKey $b
  if (-not $na -or -not $nb -or $na -eq $nb) { continue }
  [void]$oncNames.Add($na); [void]$oncNames.Add($nb)
  [void]$oncPairs.Add((Get-PairKey $na $nb))
}
Write-Host ("  onc pairs: {0}  onc names: {1}" -f $oncPairs.Count, $oncNames.Count)

Write-Host 'Building NDF-RT pairs...'
$inter = Import-Csv $ndf
$seen   = New-Object System.Collections.Generic.HashSet[string]
$rows   = New-Object System.Collections.Generic.List[object]
foreach ($p in $inter) {
  $a = ($p.'IN1-RXCUI').Trim(); $b = ($p.'IN2-RXCUI').Trim()
  if (-not $a -or -not $b -or $a -eq $b) { continue }
  $na = $nameByRxcui[$a]; $nb = $nameByRxcui[$b]
  if (-not $na -or -not $nb) { continue }
  $ka = Get-NormKey $na; $kb = Get-NormKey $nb
  $key = Get-PairKey $ka $kb
  if (-not $seen.Add($key)) { continue }
  $sev = if ($oncPairs.Contains($key)) { 'contraindicated' } else { 'reported' }
  $src = if ($sev -eq 'contraindicated') { 'ndf-rt+onc' } else { 'ndf-rt' }
  $rows.Add([pscustomobject]@{
    name_a = $na; name_b = $nb; severity = $sev
    rxcui_a = $a; rxcui_b = $b; sources = $src
  })
}
Write-Host ("  ndf-rt pairs kept: {0}" -f $rows.Count)

Write-Host 'Adding ONC pairs not already covered...'
$covered = New-Object System.Collections.Generic.HashSet[string]
foreach ($r in $rows) { [void]$covered.Add((Get-PairKey (Get-NormKey $r.name_a) (Get-NormKey $r.name_b))) }
$added = 0
foreach ($line in (Get-Content $oncFile)) {
  $parts = $line.Split('$')
  if ($parts.Count -lt 4) { continue }
  $a = $parts[0].Trim(); $b = $parts[2].Trim()
  $ka = Get-NormKey $a; $kb = Get-NormKey $b
  $key = Get-PairKey $ka $kb
  if ($covered.Contains($key)) { continue }
  [void]$covered.Add($key)
  $rows.Add([pscustomobject]@{
    name_a = (Get-DisplayName $a); name_b = (Get-DisplayName $b); severity = 'contraindicated'
    rxcui_a = ''; rxcui_b = ''; sources = 'onc'
  })
  $added++
}
Write-Host ("  onc-only pairs added: {0}" -f $added)

# ---- Optional openFDA enrichment overlay (enrich-only; never downgrades) ----
$enrichPath = if ($Enrich) { $Enrich } else { Join-Path $outDir 'ddi_openfda.csv' }
if (-not $SkipEnrich -and (Test-Path $enrichPath)) {
  Write-Host ("Applying openFDA enrichment: {0}" -f $enrichPath)
  $enrichMap = @{}
  foreach ($e in (Import-Csv $enrichPath)) {
    if (-not $e.name_a -or -not $e.name_b) { continue }
    $enrichMap[(Get-PairKey (Get-NormKey $e.name_a) (Get-NormKey $e.name_b))] = $e.severity
  }
  $upgraded = 0
  $rank = @{ 'reported' = 0; 'moderate' = 1; 'severe' = 2; 'contraindicated' = 3 }
  foreach ($r in $rows) {
    $key = Get-PairKey (Get-NormKey $r.name_a) (Get-NormKey $r.name_b)
    $grade = $enrichMap[$key]
    if ($grade -and $rank[$grade] -gt $rank[$r.severity]) {
      $r.severity = $grade
      $r.sources = "$($r.sources)+openfda"
      $upgraded++
    }
  }
  Write-Host ("  pairs upgraded from openFDA: {0}" -f $upgraded)
} else {
  Write-Host 'openFDA enrichment skipped (flag set or file absent).'
}

# ---- Optional openFDA NEW pairs (only severe/moderate-graded discoveries) ----
$newPath = Join-Path $outDir 'ddi_openfda_new.csv'
if (-not $SkipEnrich -and (Test-Path $newPath)) {
  Write-Host ("Adding openFDA new pairs: {0}" -f $newPath)
  $seen = New-Object System.Collections.Generic.HashSet[string]
  foreach ($r in $rows) {
    [void]$seen.Add((Get-PairKey (Get-NormKey $r.name_a) (Get-NormKey $r.name_b)))
  }
  $newAdded = 0
  foreach ($n in (Import-Csv $newPath)) {
    if (-not $n.name_a -or -not $n.name_b) { continue }
    $key = Get-PairKey (Get-NormKey $n.name_a) (Get-NormKey $n.name_b)
    if (-not $seen.Add($key)) { continue }
    $rows.Add([pscustomobject]@{
      name_a = $n.name_a; name_b = $n.name_b; severity = $n.severity
      rxcui_a = ''; rxcui_b = ''; sources = 'openfda(new)'
    })
    $newAdded++
  }
  Write-Host ("  new pairs added: {0}" -f $newAdded)
}

Write-Host 'Writing outputs...'
$ddiPath = Join-Path $outDir 'ddi.csv'
$rows | Export-Csv -Path $ddiPath -NoTypeInformation -Encoding UTF8
Write-Host ("  ddi.csv rows: {0}" -f $rows.Count)

$drugIndex = @{}
foreach ($r in $rows) {
  foreach ($side in @(@($r.name_a, $r.rxcui_a), @($r.name_b, $r.rxcui_b))) {
    $nm = $side[0]; $rx = $side[1]
    if (-not $nm) { continue }
    if (-not $drugIndex.ContainsKey($nm)) { $drugIndex[$nm] = $rx }
    elseif (-not $drugIndex[$nm] -and $rx) { $drugIndex[$nm] = $rx }
  }
}
$nameRows = foreach ($k in ($drugIndex.Keys | Sort-Object)) {
  [pscustomobject]@{ name = $k; rxcui = $drugIndex[$k]; source = if ($drugIndex[$k]) { 'ndf-rt' } else { 'onc' } }
}
$namesPath = Join-Path $outDir 'drug_names.csv'
$nameRows | Export-Csv -Path $namesPath -NoTypeInformation -Encoding UTF8
Write-Host ("  drug_names.csv rows: {0}" -f @($nameRows).Count)

$bySev = $rows | Group-Object severity | ForEach-Object { "{0}={1}" -f $_.Name, $_.Count }
Write-Host ("DONE. severity: {0}" -f ($bySev -join ', '))
