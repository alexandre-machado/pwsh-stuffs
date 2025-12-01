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
    $oldPci = Import-Csv $oldPciPath
    $newPci = Import-Csv $newPciPath
    $pciDiff = Compare-ObjectsByKey -Old $oldPci -New $newPci -KeyProps @("InstanceId") -ValueProps @("Status","FriendlyName","Class") -Label "PCI"
    Save-CmpCsv $pciDiff "pci-diff.csv"
    Add-Summary -Label "PCI" -Diff $pciDiff
}

# ==== Additional optional comparisons (moved out of PCI block to avoid dependency) ====
$oldNetAdvPath = Join-Path $OldSnapshotPath "network-advanced.csv"
$newNetAdvPath = Join-Path $NewSnapshotPath "network-advanced.csv"
if ((Test-Path $oldNetAdvPath) -and (Test-Path $newNetAdvPath)) {
    Write-Host "Comparando Network Advanced..." -ForegroundColor Yellow
    $oldNetAdv = Import-Csv $oldNetAdvPath
    $newNetAdv = Import-Csv $newNetAdvPath
    $netAdvDiff = Compare-ObjectsByKey -Old $oldNetAdv -New $newNetAdv -KeyProps @("Name","RegistryKeyword") -ValueProps @("DisplayValue","RegistryValue") -Label "NetworkAdvanced"
    Save-CmpCsv $netAdvDiff "network-advanced-diff.csv"
    Add-Summary -Label "NetworkAdvanced" -Diff $netAdvDiff
}

$oldNetRssPath = Join-Path $OldSnapshotPath "network-rss.csv"
$newNetRssPath = Join-Path $NewSnapshotPath "network-rss.csv"
if ((Test-Path $oldNetRssPath) -and (Test-Path $newNetRssPath)) {
    Write-Host "Comparando Network RSS..." -ForegroundColor Yellow
    $oldNetRss = Import-Csv $oldNetRssPath
    $newNetRss = Import-Csv $newNetRssPath
    $netRssDiff = Compare-ObjectsByKey -Old $oldNetRss -New $newNetRss -KeyProps @("Name") -ValueProps @("Enabled","Profile","NumberOfReceiveQueues","BaseProcessorGroup","BaseProcessorNumber","MaxProcessorNumber") -Label "NetworkRSS"
    Save-CmpCsv $netRssDiff "network-rss-diff.csv"
    Add-Summary -Label "NetworkRSS" -Diff $netRssDiff
}

$oldDiskPath = Join-Path $OldSnapshotPath "disk.csv"
$newDiskPath = Join-Path $NewSnapshotPath "disk.csv"
if ((Test-Path $oldDiskPath) -and (Test-Path $newDiskPath)) {
    Write-Host "Comparando Disks..." -ForegroundColor Yellow
    $oldDisk = Import-Csv $oldDiskPath
    $newDisk = Import-Csv $newDiskPath
    $diskDiff = Compare-ObjectsByKey -Old $oldDisk -New $newDisk -KeyProps @("FriendlyName","SerialNumber") -ValueProps @("MediaType","BusType","HealthStatus","OperationalStatus","FirmwareVersion","Size") -Label "Disk"
    Save-CmpCsv $diskDiff "disk-diff.csv"
    Add-Summary -Label "Disk" -Diff $diskDiff
}

$oldSvcPath = Join-Path $OldSnapshotPath "services.csv"
$newSvcPath = Join-Path $NewSnapshotPath "services.csv"
if ((Test-Path $oldSvcPath) -and (Test-Path $newSvcPath)) {
    Write-Host "Comparando Services..." -ForegroundColor Yellow
    $oldSvc = Import-Csv $oldSvcPath
    $newSvc = Import-Csv $newSvcPath
    $svcDiff = Compare-ObjectsByKey -Old $oldSvc -New $newSvc -KeyProps @("Name") -ValueProps @("Status","StartType","DisplayName") -Label "Services"
    Save-CmpCsv $svcDiff "services-diff.csv"
    Add-Summary -Label "Services" -Diff $svcDiff
}

$oldNetStatsPath = Join-Path $OldSnapshotPath "network-stats.csv"
$newNetStatsPath = Join-Path $NewSnapshotPath "network-stats.csv"
if ((Test-Path $oldNetStatsPath) -and (Test-Path $newNetStatsPath)) {
    Write-Host "Comparando Network Stats..." -ForegroundColor Yellow
    $oldNetStats = Import-Csv $oldNetStatsPath
    $newNetStats = Import-Csv $newNetStatsPath
    $netStatsDiff = Compare-ObjectsByKey -Old $oldNetStats -New $newNetStats -KeyProps @("Name") -ValueProps @("ReceivedBytes","SentBytes","ReceivedUnicastPackets","SentUnicastPackets") -Label "NetworkStats"
    Save-CmpCsv $netStatsDiff "network-stats-diff.csv"
    Add-Summary -Label "NetworkStats" -Diff $netStatsDiff
}

$oldEventsPath = Join-Path $OldSnapshotPath "system-events.csv"
$newEventsPath = Join-Path $NewSnapshotPath "system-events.csv"
if ((Test-Path $oldEventsPath) -and (Test-Path $newEventsPath)) {
    Write-Host "Comparando System Events..." -ForegroundColor Yellow
    $oldEvents = Import-Csv $oldEventsPath
    $newEvents = Import-Csv $newEventsPath
    $eventsDiff = Compare-ObjectsByKey -Old $oldEvents -New $newEvents -KeyProps @("TimeCreated","ProviderName","Id") -ValueProps @("LevelDisplayName") -Label "SystemEvents"
    Save-CmpCsv $eventsDiff "system-events-diff.csv"
    Add-Summary -Label "SystemEvents" -Diff $eventsDiff
}

$oldDGPath = Join-Path $OldSnapshotPath "deviceguard.csv"
$newDGPath = Join-Path $NewSnapshotPath "deviceguard.csv"
if ((Test-Path $oldDGPath) -and (Test-Path $newDGPath)) {
    Write-Host "Comparando DeviceGuard..." -ForegroundColor Yellow
    $oldDG = Import-Csv $oldDGPath
    $newDG = Import-Csv $newDGPath
    $dgDiff = Compare-ObjectsByKey -Old $oldDG -New $newDG -KeyProps @("SecurityServicesConfigured","SecurityServicesRunning") -ValueProps @() -Label "DeviceGuard"
    Save-CmpCsv $dgDiff "deviceguard-diff.csv"
    Add-Summary -Label "DeviceGuard" -Diff $dgDiff
}

$oldHvPath = Join-Path $OldSnapshotPath "hypervisor.csv"
$newHvPath = Join-Path $NewSnapshotPath "hypervisor.csv"
if ((Test-Path $oldHvPath) -and (Test-Path $newHvPath)) {
    Write-Host "Comparando Hypervisor State..." -ForegroundColor Yellow
    $oldHv = Import-Csv $oldHvPath
    $newHv = Import-Csv $newHvPath
    $hvDiff = Compare-ObjectsByKey -Old $oldHv -New $newHv -KeyProps @("Key") -ValueProps @("Value") -Label "Hypervisor"
    Save-CmpCsv $hvDiff "hypervisor-diff.csv"
    Add-Summary -Label "Hypervisor" -Diff $hvDiff
}

$oldTopTalkersPath = Join-Path $OldSnapshotPath "net-top-talkers.csv"
$newTopTalkersPath = Join-Path $NewSnapshotPath "net-top-talkers.csv"
if ((Test-Path $oldTopTalkersPath) -and (Test-Path $newTopTalkersPath)) {
    Write-Host "Comparando Network Top Talkers..." -ForegroundColor Yellow
    $oldTT = Import-Csv $oldTopTalkersPath
    $newTT = Import-Csv $newTopTalkersPath
    $ttDiff = Compare-ObjectsByKey -Old $oldTT -New $newTT -KeyProps @("OwningProcess") -ValueProps @("ConnectionCount","ProcessName") -Label "NetTopTalkers"
    Save-CmpCsv $ttDiff "net-top-talkers-diff.csv"
    Add-Summary -Label "NetTopTalkers" -Diff $ttDiff
}

$oldProcIoPath = Join-Path $OldSnapshotPath "process-io.csv"
$newProcIoPath = Join-Path $NewSnapshotPath "process-io.csv"
if ((Test-Path $oldProcIoPath) -and (Test-Path $newProcIoPath)) {
    Write-Host "Comparando Process IO..." -ForegroundColor Yellow
    $oldPIO = Import-Csv $oldProcIoPath
    $newPIO = Import-Csv $newProcIoPath
    $pioDiff = Compare-ObjectsByKey -Old $oldPIO -New $newPIO -KeyProps @("Id","Name") -ValueProps @("IOReadBytes","IOWriteBytes") -Label "ProcessIO"
    Save-CmpCsv $pioDiff "process-io-diff.csv"
    Add-Summary -Label "ProcessIO" -Diff $pioDiff
}

$oldExtraPath = Join-Path $OldSnapshotPath "extra-counters.csv"
$newExtraPath = Join-Path $NewSnapshotPath "extra-counters.csv"
if ((Test-Path $oldExtraPath) -and (Test-Path $newExtraPath)) {
    Write-Host "Comparando Extra Counters..." -ForegroundColor Yellow
    $oldExtra = Import-Csv $oldExtraPath
    $newExtra = Import-Csv $newExtraPath
    $extraDiff = Compare-ObjectsByKey -Old $oldExtra -New $newExtra -KeyProps @("Path") -ValueProps @("CookedValue") -Label "ExtraCounters"
    Save-CmpCsv $extraDiff "extra-counters-diff.csv"
    Add-Summary -Label "ExtraCounters" -Diff $extraDiff
}

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
