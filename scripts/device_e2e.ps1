#===============================================================================
# HealthGuardian on-device E2E harness.
#
# Drives the real APK over adb by reading the accessibility tree
# (uiautomator dump) and tapping node centers, then asserts the expected
# screens appear. On any mismatch it prints diagnostics, saves a screencap
# and logcat, resets the app, and moves on to the next scenario.
#
# Requires: adb on PATH, a device connected (default serial ee783d64),
# and the debug/release APK already installed.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\device_e2e.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\device_e2e.ps1 -Scenario adultNormal
#   powershell -ExecutionPolicy Bypass -File scripts\device_e2e.ps1 -List
#===============================================================================
param(
    [string]$Serial = 'ee783d64',
    [string]$Package = 'com.healthguardian.healthguardian',
    [string]$Activity = '.MainActivity',
    [string]$OutDir = "$env:TEMP\opencode\e2e-artifacts",
    [string]$Scenario = '',
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$nl = [char]10

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & adb -s $Serial @Args 2>&1
    $ErrorActionPreference = $old
    return $out
}

function Read-XmlNodes {
    $local = Join-Path $OutDir 'hc_e2e.xml'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-Adb shell uiautomator dump /sdcard/hc_e2e.xml | Out-Null
            Invoke-Adb pull /sdcard/hc_e2e.xml $local | Out-Null
            [xml]$doc = [System.IO.File]::ReadAllText($local)
            $result = @()
            foreach ($n in $doc.SelectNodes('//node')) {
                $d = $n.'content-desc'
                if ([string]::IsNullOrWhiteSpace($d)) { continue }
                $b = $n.bounds
                if ($b -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
                    $result += [pscustomobject]@{
                        desc = $d
                        x1   = [int]$matches[1]
                        y1   = [int]$matches[2]
                        x2   = [int]$matches[3]
                        y2   = [int]$matches[4]
                        cx   = [int](([int]$matches[1] + [int]$matches[3]) / 2)
                        cy   = [int](([int]$matches[2] + [int]$matches[4]) / 2)
                    }
                }
            }
            return $result
        } catch {
            if ($attempt -eq 3) {
                throw "uiautomator dump failed after 3 tries: $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds 800
        }
    }
}

function Find-Node {
    param($Nodes, [string]$Sub)
    foreach ($n in $Nodes) {
        if ($n.desc -eq $Sub) { return $n }
    }
    $best = $null
    foreach ($n in $Nodes) {
        if ($n.desc.Contains($Sub)) {
            if (-not $best -or $n.desc.Length -lt $best.desc.Length) {
                $best = $n
            }
        }
    }
    return $best
}

function Tap-Node {
    param($Node)
    Write-Host "    tap '$($Node.desc -replace "[$nl]+", ' | ')' @ $($Node.cx),$($Node.cy)"
    Invoke-Adb shell input tap $($Node.cx) $($Node.cy) | Out-Null
    Start-Sleep -Milliseconds 800
}

function Tap-Scroll {
    param(
        [string]$Sub,
        [int]$MaxSwipes = 8,
        [string]$Direction = 'up'
    )
    $swipes = 0
    while ($true) {
        $nodes = Read-XmlNodes
        $n = Find-Node $nodes $Sub
        if ($n) { Tap-Node $n; return }
        if ($swipes -ge $MaxSwipes) {
            throw "Tap target not found after $MaxSwipes swipes: '$Sub'"
        }
        if ($Direction -eq 'up') {
            Invoke-Adb shell input swipe 540 1900 540 500 300
        } else {
            Invoke-Adb shell input swipe 540 500 540 1900 300
        }
        Start-Sleep -Milliseconds 700
        $swipes++
    }
}

# Tap the value display of a stepper, clear the prefilled text, type a number
# into the dialog, and confirm with the Save button.
function Set-StepperValue {
    param([string]$Unit, [string]$Digits)
    $n = Find-Node (Read-XmlNodes) "$Unit, tap to edit"
    if (-not $n) {
        # fall back to any node whose desc ends with 'tap to edit'
        $n = (Read-XmlNodes) | Where-Object { $_.desc -like '*tap to edit*' } |
            Sort-Object { $_.desc.Length } | Select-Object -First 1
    }
    if (-not $n) { throw "Stepper value display not found for unit '$Unit'" }
    Tap-Node $n
    # Clear the prefilled value (move to end, delete all, DEL for each digit).
    Invoke-Adb shell input keyevent KEYCODE_MOVE_END | Out-Null
    for ($i = 0; $i -lt 12; $i++) {
        Invoke-Adb shell input keyevent KEYCODE_DEL | Out-Null
    }
    Start-Sleep -Milliseconds 400
    Invoke-Adb shell input text $Digits | Out-Null
    Start-Sleep -Milliseconds 600
    $save = Find-Node (Read-XmlNodes) 'Save'
    if (-not $save) { throw "Save button not found on value dialog" }
    Tap-Node $save
}

function Tap-RowControl {
    param([string]$RowSub, [string]$Ctrl = 'Yes', [int]$MaxSwipes = 8)
    $swipes = 0
    while ($true) {
        $nodes = Read-XmlNodes
        $row = Find-Node $nodes $RowSub
        if (-not $row) {
            if ($swipes -ge $MaxSwipes) {
                throw "Row not found after $MaxSwipes swipes: '$RowSub'"
            }
            Invoke-Adb shell input swipe 540 1900 540 500 300
            Start-Sleep -Milliseconds 700
            $swipes++
            continue
        }
        $best = $null
        foreach ($n in ($nodes | Where-Object { $_.desc.Contains($Ctrl) } | Sort-Object cy)) {
            if ($n.cy -ge $row.y1) { $best = $n; break }
        }
        if (-not $best) {
            if ($swipes -ge $MaxSwipes) {
                throw "Control '$Ctrl' not visible near row: '$RowSub'"
            }
            Invoke-Adb shell input swipe 540 1900 540 500 300
            Start-Sleep -Milliseconds 700
            $swipes++
            continue
        }
        Tap-Node $best
        return
    }
}

function Assert-Desc {
    param([string]$Sub)
    $nodes = Read-XmlNodes
    if (-not (Find-Node $nodes $Sub)) {
        throw "Screen missing expected text: '$Sub'"
    }
    Write-Host "    ok: '$Sub'"
}

function Assert-TierCode {
    $nodes = Read-XmlNodes
    foreach ($n in $nodes) {
        if ($n.desc -match 'P[1-5] - ') {
            Write-Host "    ok: tier '$($n.desc -replace "[$nl]+", ' | ')'"
            return
        }
    }
    throw 'No tier code (P1-P5) found on result screen'
}

function Wait-Desc {
    param([string]$Sub, [int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $nodes = Read-XmlNodes
            if (Find-Node $nodes $Sub) { return }
        } catch {}
        Start-Sleep -Milliseconds 1200
    }
    throw "Timed out waiting for text: '$Sub'"
}

function Reset-App {
    Invoke-Adb shell am force-stop $Package | Out-Null
    Start-Sleep -Milliseconds 800
    Invoke-Adb shell am start -n "$Package/$Activity" | Out-Null
    Wait-Desc 'Start Triage'
}

function Save-Diagnostics {
    param([string]$Prefix, [hashtable]$Step)
    try {
        $cap = Join-Path $OutDir ($Prefix + '.png')
        & cmd /c "adb -s $Serial exec-out screencap -p > `"$cap`"" 2>&1 | Out-Null
        Write-Host "    screencap saved: $cap"
    } catch { Write-Host "    screencap failed: $($_.Exception.Message)" }
    try {
        $lg = Invoke-Adb logcat -d -t 300 | Where-Object { $_ -match $Package } | Select-Object -Last 20
        Write-Host '    --- logcat (tail) ---'
        $lg | ForEach-Object { Write-Host "    $_" }
    } catch {}
}

#-------------------------------------------------------------------------------
# Scenarios: adult = NEWS2, children = Peds-NEWS2, newborn = PEWS.
#  tap   = scroll-until-visible then tap the node containing this text
#  rowTap/ctrl = tap the Yes/No control nearest the row containing this text
#  assert= the current screen must contain this text
#  assertTier = a P1..P5 result banner must be on screen
#-------------------------------------------------------------------------------
$scenarios = @(
    @{ Name = 'adultNormal'; Steps = @(
        @{ tap = 'Start Triage' },
        @{ tap = '16 - 64 years' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' }, # rr
        @{ tap = 'Continue' }, # spo2
        @{ tap = 'Continue' }, # sbp
        @{ tap = 'Continue' }, # hr
        @{ tap = 'Continue' }, # temp
        @{ tap = 'Continue' }, # onOxygen
        @{ tap = 'Continue' }, # copd
        @{ tap = 'Alert (A)' },
        @{ tap = 'Continue' },
        @{ tap = 'Chest pain' },
        @{ tap = 'Continue' }, # probes, all No
        @{ assert = 'P5 - Minor' },
        @{ assert = 'NEWS2 score' }
    )},
    @{ Name = 'adultFeverGcsSepsis'; Steps = @(
        @{ tap = 'Start Triage' },
        @{ tap = '16 - 64 years' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' }, # rr
        @{ tap = 'Continue' }, # spo2
        @{ tap = 'Continue' }, # sbp
        @{ tap = 'Continue' }, # hr
        @{ tap = 'Continue' }, # temp
        @{ tap = 'Continue' }, # onOxygen
        @{ tap = 'Continue' }, # copd
        @{ tap = 'Voice (V)' },
        @{ tap = 'Continue' },
        @{ tap = 'Fever' },
        @{ tap = 'Spontaneous' },
        @{ tap = 'Continue' },
        @{ tap = 'Oriented' },
        @{ tap = 'Continue' },
        @{ tap = 'Obeys' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' }, # fever probes, all No
        @{ assert = 'Sepsis screening questions' },
        @{ tap = 'Continue' },
        @{ assert = 'NEWS2 score' },
        @{ assert = 'GCS: 15' },
        @{ assert = 'qSOFA 1' },
        @{ assert = 'P2 - Very Urgent' }
    )},
    @{ Name = 'toddlerPedsNews2CapRefill'; Steps = @(
        @{ tap = 'Start Triage' },
        @{ tap = '1 - 2 years' },
        @{ tap = 'Continue' },
        @{ tap = '24 /min' },  # toddler normal RR
        @{ tap = 'Continue' },
        @{ tap = '98 %' },     # SpO2
        @{ tap = 'Continue' },
        @{ type = $true; unit = 'bpm'; value = '110' }, # toddler normal HR (91-150)
        @{ tap = 'Continue' },
        @{ tap = 'Continue' }, # temp 37
        @{ tap = 'Less than 2 seconds' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' }, # onOxygen -> No
        @{ tap = 'Alert (A)' },
        @{ tap = 'Continue' },
        @{ tap = 'Chest pain' },
        @{ tap = 'Continue' }, # chest probes, all No
        @{ assert = 'Peds-NEWS2 score' },
        @{ assert = 'Blood pressure not measured (optional for this age group).' },
        @{ assert = 'P5 - Minor' }
    )},
    @{ Name = 'newbornPewsFeedingReview'; Steps = @(
        @{ tap = 'Start Triage' },
        @{ tap = 'Less than 1 month old' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' }, # rr 48
        @{ tap = 'Continue' }, # spo2 97
        @{ tap = 'Continue' }, # hr 140
        @{ tap = 'Continue' }, # temp 37
        @{ tap = 'Alert, feeding well' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' }, # onOxygen -> No
        @{ tap = 'Fever' },
        @{ tap = 'Continue' }, # fever probes, all No
        @{ assert = 'Sepsis screening questions' },
        @{ tap = 'Continue' },
        @{ assert = 'PEWS score' },
        @{ assert = 'P4 - ' }
    )},
    @{ Name = 'adultDangerP1'; Steps = @(
        @{ tap = 'Start Triage' },
        @{ tap = '16 - 64 years' },
        @{ tap = 'Yes' },      # first danger row
        @{ swipe = 'up' },     # expanded row pushes Continue below the fold
        @{ tap = 'Continue' },
        @{ assert = 'P1 - Emergency' },
        @{ assert = 'danger sign triggered this result' }
    )},
    @{ Name = 'adultTearBackPainP1'; Steps = @(
        @{ tap = 'Start Triage' },
        @{ tap = '16 - 64 years' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' },
        @{ tap = 'Continue' },
        @{ tap = 'Alert (A)' },
        @{ tap = 'Continue' },
        @{ tap = 'Chest pain' },
        @{ rowTap = 'tearing pain'; ctrl = 'Yes' },
        @{ tap = 'Continue' },
        @{ assert = 'P1 - Emergency' }
    )}
)

if ($List) {
    $scenarios | ForEach-Object { Write-Host $_.Name }
    exit 0
}

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$state = Invoke-Adb get-state
if ($state -notmatch 'device') { Write-Host "ERROR: adb device state = $state" -ForegroundColor Red; exit 2 }

$selected = @()
if ($Scenario -ne '') {
    $selected = @($scenarios | Where-Object { $_.Name -eq $Scenario })
    if ($selected.Count -eq 0) { Write-Host "Unknown scenario: $Scenario"; exit 2 }
} else {
    $selected = $scenarios
}

$failures = @()
foreach ($sc in $selected) {
    Write-Host ''
    Write-Host "=== $($sc.Name) ==="
    $prefix = ($sc.Name + '_' + (Get-Date -Format 'HHmmss'))
    try {
        Reset-App
        $idx = 0
        foreach ($step in $sc.Steps) {
            $idx++
            if ($step.ContainsKey('tap')) { Tap-Scroll $step.tap }
            elseif ($step.ContainsKey('swipe')) {
                if ($step.swipe -eq 'down') {
                    Invoke-Adb shell input swipe 540 500 540 1900 300
                } else {
                    Invoke-Adb shell input swipe 540 1900 540 500 300
                }
                Start-Sleep -Milliseconds 700
            }
            elseif ($step.ContainsKey('rep')) {
                $times = if ($step.ContainsKey('times')) { $step.times } else { 3 }
                for ($t = 0; $t -lt $times; $t++) { Tap-Scroll $step.rep }
            }
            elseif ($step.ContainsKey('type')) { Set-StepperValue $step.unit $step.value }
            elseif ($step.ContainsKey('rowTap')) { Tap-RowControl $step.rowTap $step.ctrl }
            elseif ($step.ContainsKey('assertTier')) { Assert-TierCode }
            elseif ($step.ContainsKey('assert')) { Assert-Desc $step.assert }
            else { throw "Unknown step type at step $idx" }
        }
        Write-Host "    >>> PASS"
    } catch {
        Write-Host "    >>> FAIL at step $idx : $($_.Exception.Message)" -ForegroundColor Red
        try {
            $nodes = Read-XmlNodes
            Write-Host '    --- current screen descs ---'
            $nodes | Select-Object -First 40 | ForEach-Object {
                Write-Host ("    " + ($_.desc -replace "[$nl]+", ' | '))
            }
        } catch {}
        Save-Diagnostics $prefix $step
        $failures += $sc.Name
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures.Count) of $($selected.Count) scenarios:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" }
    Write-Host "Artifacts in: $OutDir"
    exit 1
} else {
    Write-Host "ALL $($selected.Count) scenarios PASSED."
    exit 0
}