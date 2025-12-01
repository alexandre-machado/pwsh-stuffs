param(
    [Parameter(Mandatory = $true)]
    [string]$OldSnapshotPath,

    [Parameter(Mandatory = $true)]
    [string]$NewSnapshotPath,

    [string]$OutDir = "."
)

# ========== PREPARO ==========
if (-not (Test-Path $OldSnapshotPath)) {
    Write-Host "OldSnapshotPath não existe: $OldSnapshotPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $NewSnapshotPath)) {
    Write-Host "NewSnapshotPath não existe: $NewSnapshotPath" -ForegroundColor Red
    exit 1
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$compareFolder = Join-Path $OutDir "compare-$(Split-Path $OldSnapshotPath -Leaf)_vs_$(Split-Path $NewSnapshotPath -Leaf)_$timestamp"
New-Item -ItemType Directory -Force -Path $compareFolder | Out-Null

Write-Host "Gerando comparação em: $compareFolder" -ForegroundColor Cyan

# Helper para salvar CSV
function Save-Csv {
    param(
        [Parameter(Mandatory = $true)] $Data,
        [Parameter(Mandatory = $true)] [string]$Name
    )
    $path = Join-Path $compareFolder $Name
    $Data | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $path
    Write-Host " ✓ $Name" -ForegroundColor Green
}

# Helper genérico p/ comparar duas listas de objetos
function Compare-ObjectsByKey {
    param(
        [Parameter(Mandatory = $true)] $Old,
        [Parameter(Mandatory = $true)] $New,
        [string[]]$KeyProps,
        [string[]]$ValueProps,
        [string]$Label
    )

    $results = New-Object System.Collections.Generic.List[object]

    # Index
    $oldIndex = @{}
    foreach ($o in $Old) {
        $k = ($KeyProps | ForEach-Object { ($o.$_) }) -join '||'
        if (-not $oldIndex.ContainsKey($k)) { $oldIndex[$k] = $o }
    }

    $newIndex = @{}
    foreach ($n in $New) {
        $k = ($KeyProps | ForEach-Object { ($n.$_) }) -join '||'
        if (-not $newIndex.ContainsKey($k)) { $newIndex[$k] = $n }
    }

    $allKeys = New-Object System.Collections.Generic.HashSet[string]
    $oldIndex.Keys | ForEach-Object { $allKeys.Add($_) | Out-Null }
    $newIndex.Keys | ForEach-Object { $allKeys.Add($_) | Out-Null }

    foreach ($k in $allKeys) {
        $oldObj = $null
        $newObj = $null
        $oldIndex.TryGetValue($k, [ref]$oldObj) | Out-Null
        $newIndex.TryGetValue($k, [ref]$newObj) | Out-Null

        $changeType = $null
        if ($oldObj -and -not $newObj) {
            $changeType = "Removed"
        } elseif (-not $oldObj -and $newObj) {
            $changeType = "Added"
        } else {
            # Existe nos dois -> verificar se mudou
            $changed = $false
            foreach ($p in $ValueProps) {
                $oldVal = $oldObj.$p
                $newVal = $newObj.$p
                if ("$oldVal" -ne "$newVal") {
                    $changed = $true
                    break
                }
            }
            $changeType = $changed ? "Changed" : "Unchanged"
            if (-not $changed) {
                # se não quer listar Unchanged, comenta a próxima linha
                continue
            }
        }

        $out = [ordered]@{
            Category   = $Label
            ChangeType = $changeType
        }

        # Chaves
        if ($oldObj) {
            foreach ($p in $KeyProps) { $out["Key_$p"] = $oldObj.$p }
        } elseif ($newObj) {
            foreach ($p in $KeyProps) { $out["Key_$p"] = $newObj.$p }
        }

        # Valores
        foreach ($p in $ValueProps) {
            $out["Old_$p"] = $oldObj ? $oldObj.$p : $null
            $out["New_$p"] = $newObj ? $newObj.$p : $null
        }

        $results.Add([pscustomobject]$out) | Out-Null
    }

    return $results
}

# Contador p/ summary
$summary = New-Object System.Collections.Generic.List[object]

function Add-Summary {
    param(
        [string]$Label,
        $Diff
    )
    if (-not $Diff) {
        $summary.Add([pscustomobject]@{
            Category = $Label
            Added    = 0
            Removed  = 0
            Changed  = 0
        }) | Out-Null
        return
    }

    $added   = ($Diff | Where-Object { $_.ChangeType -eq "Added"   }).Count
    $removed = ($Diff | Where-Object { $_.ChangeType -eq "Removed" }).Count
    $changed = ($Diff | Where-Object { $_.ChangeType -eq "Changed" }).Count

    $summary.Add([pscustomobject]@{
        Category = $Label
        Added    = $added
        Removed  = $removed
        Changed  = $changed
    }) | Out-Null
}

# ========== DRIVERS ==========
$oldDriversPath = Join-Path $OldSnapshotPath "drivers.csv"
$newDriversPath = Join-Path $NewSnapshotPath "drivers.csv"
if (Test-Path $oldDriversPath -and Test-Path $newDriversPath) {
    Write-Host "Comparando drivers..." -ForegroundColor Yellow
    $oldDrivers = Import-Csv $oldDriversPath
    $newDrivers = Import-Csv $newDriversPath

    $driversDiff = Compare-ObjectsByKey `
        -Old $oldDrivers `
        -New $newDrivers `
        -KeyProps @("DeviceID","Driver") `
        -ValueProps @("DriverVersion","DriverDate","DriverProviderName","Path") `
        -Label "Drivers"

    Save-Csv $driversDiff "drivers-diff.csv"
    Add-Summary -Label "Drivers" -Diff $driversDiff
} else {
    Write-Host "drivers.csv não encontrado em um dos snapshots." -ForegroundColor DarkYellow
}

# ========== INTERRUPTS ==========
$oldIntPath = Join-Path $OldSnapshotPath "interrupts.csv"
$newIntPath = Join-Path $NewSnapshotPath "interrupts.csv"
if (Test-Path $oldIntPath -and Test-Path $newIntPath) {
    Write-Host "Comparando interrupts/DPC..." -ForegroundColor Yellow
    $oldInt = Import-Csv $oldIntPath
    $newInt = Import-Csv $newIntPath

    # Path é o CounterPath; CookedValue é o valor em si
    $intDiff = Compare-ObjectsByKey `
        -Old $oldInt `
        -New $newInt `
        -KeyProps @("Path") `
        -ValueProps @("CookedValue") `
        -Label "Interrupts"

    Save-Csv $intDiff "interrupts-diff.csv"
    Add-Summary -Label "Interrupts/DPC" -Diff $intDiff
} else {
    Write-Host "interrupts.csv não encontrado em um dos snapshots." -ForegroundColor DarkYellow
}

# ========== CPU ==========
$oldCpuPath = Join-Path $OldSnapshotPath "cpu.csv"
$newCpuPath = Join-Path $NewSnapshotPath "cpu.csv"
if (Test-Path $oldCpuPath -and Test-Path $newCpuPath) {
    Write-Host "Comparando CPU..." -ForegroundColor Yellow
    $oldCpu = Import-Csv $oldCpuPath
    $newCpu = Import-Csv $newCpuPath

    $cpuDiff = Compare-ObjectsByKey `
        -Old $oldCpu `
        -New $newCpu `
        -KeyProps @("Path") `
        -ValueProps @("CookedValue") `
        -Label "CPU"

    Save-Csv $cpuDiff "cpu-diff.csv"
    Add-Summary -Label "CPU" -Diff $cpuDiff
} else {
    Write-Host "cpu.csv não encontrado em um dos snapshots." -ForegroundColor DarkYellow
}

# ========== USB ==========
$oldUsbPath = Join-Path $OldSnapshotPath "usb.csv"
$newUsbPath = Join-Path $NewSnapshotPath "usb.csv"
if (Test-Path $oldUsbPath -and Test-Path $newUsbPath) {
    Write-Host "Comparando USB..." -ForegroundColor Yellow
    $oldUsb = Import-Csv $oldUsbPath
    $newUsb = Import-Csv $newUsbPath

    $usbDiff = Compare-ObjectsByKey `
        -Old $oldUsb `
        -New $newUsb `
        -KeyProps @("InstanceId") `
        -ValueProps @("Status","FriendlyName") `
        -Label "USB"

    Save-Csv $usbDiff "usb-diff.csv"
    Add-Summary -Label "USB" -Diff $usbDiff
} else {
    Write-Host "usb.csv não encontrado em um dos snapshots." -ForegroundColor DarkYellow
}

# ========== NETWORK ==========
$oldNetPath = Join-Path $OldSnapshotPath "network.csv"
$newNetPath = Join-Path $NewSnapshotPath "network.csv"
if (Test-Path $oldNetPath -and Test-Path $newNetPath) {
    Write-Host "Comparando Network..." -ForegroundColor Yellow
    $oldNet = Import-Csv $oldNetPath
    $newNet = Import-Csv $newNetPath

    $netDiff = Compare-ObjectsByKey `
        -Old $oldNet `
        -New $newNet `
        -KeyProps @("Name") `
        -ValueProps @("Status","InterfaceDescription","DriverInformation") `
        -Label "Network"

    Save-Csv $netDiff "network-diff.csv"
    Add-Summary -Label "Network" -Diff $netDiff
} else {
    Write-Host "network.csv não encontrado em um dos snapshots." -ForegroundColor DarkYellow
}

# ========== PCI ==========
$oldPciPath = Join-Path $OldSnapshotPath "pci.csv"
$newPciPath = Join-Path $NewSnapshotPath "pci.csv"
if (Test-Path $oldPciPath -and Test-Path $newPciPath) {
    Write-Host "Comparando PCI..." -ForegroundColor Yellow
    $oldPci = Import-Csv $oldPciPath
    $newPci = Import-Csv $newPciPath

    $pciDiff = Compare-ObjectsByKey `
        -Old $oldPci `
        -New $newPci `
        -KeyProps @("InstanceId") `
        -ValueProps @("Status","FriendlyName","Class") `
        -Label "PCI"

    Save-Csv $pciDiff "pci-diff.csv"
    Add-Summary -Label "PCI" -Diff $pciDiff
} else {
    Write-Host "pci.csv não encontrado em um dos snapshots." -ForegroundColor DarkYellow
}

# ========== SUMMARY ==========
$summaryPath = Join-Path $compareFolder "summary.csv"
$summary | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $summaryPath
Write-Host "`nResumo salvo em summary.csv" -ForegroundColor Cyan
Write-Host "Comparação concluída em: $compareFolder" -ForegroundColor Cyan
