param(
    [string]$OutRoot = "./analysis",
    [string]$LabelA = "before",
    [string]$LabelB = "after",
    [switch]$IncludeWprTrace,
    [int]$WprDurationSeconds = 30,
    [int]$PauseSeconds = 0,
    [switch]$InteractivePause,
    [bool]$IncludeExtraCounters,
    [bool]$CollectNetworkAdvanced,
    [bool]$CollectNetworkStats,
    [bool]$CollectSystemEvents,
    [bool]$CollectSecurityState,
    [bool]$CollectProcessIO,
    [bool]$CollectDiskInfo,
    [bool]$CollectServices
)

# Set default toggles when not explicitly provided
if (-not $PSBoundParameters.ContainsKey('IncludeExtraCounters'))   { $IncludeExtraCounters   = $true }
if (-not $PSBoundParameters.ContainsKey('CollectNetworkAdvanced')) { $CollectNetworkAdvanced = $true }
if (-not $PSBoundParameters.ContainsKey('CollectNetworkStats'))    { $CollectNetworkStats    = $true }
if (-not $PSBoundParameters.ContainsKey('CollectDiskInfo'))        { $CollectDiskInfo        = $true }
if (-not $PSBoundParameters.ContainsKey('CollectServices'))        { $CollectServices        = $true }
if (-not $PSBoundParameters.ContainsKey('CollectSystemEvents'))    { $CollectSystemEvents    = $false }
if (-not $PSBoundParameters.ContainsKey('CollectSecurityState'))   { $CollectSecurityState   = $false }
if (-not $PSBoundParameters.ContainsKey('CollectProcessIO'))       { $CollectProcessIO       = $false }

function New-StampFolder($base, $prefix) {
    $ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $path = Join-Path $base "$prefix-$ts"
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Save-Csv($data, $path) {
    $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
}

function New-SystemSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$Folder
    )
    Write-Host "Creating snapshot at: $Folder" -ForegroundColor Cyan

    New-Item -ItemType Directory -Force -Path $Folder | Out-Null

    Write-Host "Collecting loaded drivers..." -ForegroundColor Yellow
    $drivers = Get-WmiObject Win32_PnPSignedDriver |
        Select-Object DeviceName, DriverProviderName, DriverVersion, DriverDate,
                      IsSigned, Driver, InfName, Manufacturer, DeviceID, DriverClass, Path
    Save-Csv $drivers (Join-Path $Folder "drivers.csv")

    Write-Host "Collecting CPU state..." -ForegroundColor Yellow
    $cpu = Get-Counter "\Processor Information(*)\Processor Frequency",
                       "\Processor Information(*)\% Processor Time",
                       "\Processor Information(*)\% Privileged Time"
    Save-Csv $cpu.CounterSamples (Join-Path $Folder "cpu.csv")

    Write-Host "Collecting ISR/DPC..." -ForegroundColor Yellow
    $interrupts = Get-Counter "\Processor(*)\Interrupts/sec",
                              "\Processor(*)\DPC Rate",
                              "\Processor(*)\% DPC Time"
    Save-Csv $interrupts.CounterSamples (Join-Path $Folder "interrupts.csv")

    Write-Host "Collecting USB devices..." -ForegroundColor Yellow
    $usb = Get-PnpDevice -Class USB | Select-Object Status, Class, FriendlyName, InstanceId
    Save-Csv $usb (Join-Path $Folder "usb.csv")

    Write-Host "Collecting network adapters..." -ForegroundColor Yellow
    $net = Get-NetAdapter | Select-Object Name, Status, InterfaceDescription, DriverInformation
    Save-Csv $net (Join-Path $Folder "network.csv")

    Write-Host "Collecting PCI devices..." -ForegroundColor Yellow
    $pci = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "PCI*" } |
            Select-Object Status, Class, FriendlyName, InstanceId
    Save-Csv $pci (Join-Path $Folder "pci.csv")

    if ($CollectNetworkAdvanced) {
        Write-Host "Collecting network advanced properties..." -ForegroundColor Yellow
        try {
            $netAdv = Get-NetAdapterAdvancedProperty -Name * -ErrorAction Stop |
                Select-Object Name, DisplayName, DisplayValue, RegistryKeyword, RegistryValue
            Save-Csv $netAdv (Join-Path $Folder "network-advanced.csv")
        } catch {
            Write-Host "Failed to collect network advanced properties: $_" -ForegroundColor DarkYellow
        }
        Write-Host "Collecting network RSS settings..." -ForegroundColor Yellow
        try {
            $netRss = Get-NetAdapterRss -Name * -ErrorAction Stop |
                Select-Object Name, Enabled, Profile, NumberOfReceiveQueues, BaseProcessorGroup, BaseProcessorNumber, MaxProcessorNumber
            Save-Csv $netRss (Join-Path $Folder "network-rss.csv")
        } catch {
            Write-Host "Failed to collect network RSS settings: $_" -ForegroundColor DarkYellow
        }
    }

    if ($CollectNetworkStats) {
        Write-Host "Collecting network adapter statistics..." -ForegroundColor Yellow
        try {
            $netStats = Get-NetAdapterStatistics -Name * -ErrorAction Stop |
                Select-Object Name, ReceivedBytes, SentBytes, ReceivedUnicastPackets, SentUnicastPackets, ReceivedBroadcastPackets, SentBroadcastPackets, ReceivedMulticastPackets, SentMulticastPackets
            Save-Csv $netStats (Join-Path $Folder "network-stats.csv")
        } catch {
            Write-Host "Failed to collect network stats: $_" -ForegroundColor DarkYellow
        }
    }

    if ($CollectDiskInfo) {
        Write-Host "Collecting physical disk info..." -ForegroundColor Yellow
        try {
            $disks = Get-PhysicalDisk |
                Select-Object FriendlyName, SerialNumber, MediaType, BusType, CanPool, HealthStatus, OperationalStatus, FirmwareVersion, Size, UniqueId
            Save-Csv $disks (Join-Path $Folder "disk.csv")
        } catch {
            Write-Host "Failed to collect physical disks: $_" -ForegroundColor DarkYellow
        }
    }

    if ($CollectServices) {
        Write-Host "Collecting services..." -ForegroundColor Yellow
        try {
            $services = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
                Select-Object Name, DisplayName, @{n='Status';e={$_.State}}, @{n='StartType';e={$_.StartMode}}
            Save-Csv $services (Join-Path $Folder "services.csv")
        } catch {
            Write-Host "CIM service query failed, falling back to Get-Service: $_" -ForegroundColor DarkYellow
            try {
                $services = Get-Service -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType
                Save-Csv $services (Join-Path $Folder "services.csv")
            } catch {
                Write-Host "Failed to collect services: $_" -ForegroundColor DarkYellow
            }
        }
    }

    if ($IncludeExtraCounters) {
        Write-Host "Collecting extra counters..." -ForegroundColor Yellow
        try {
            $extra = Get-Counter "\Processor(*)\% Interrupt Time", "\System\Context Switches/sec"
            Save-Csv $extra.CounterSamples (Join-Path $Folder "extra-counters.csv")
        } catch {
            Write-Host "Failed to collect extra counters: $_" -ForegroundColor DarkYellow
        }
    }

    if ($CollectSystemEvents) {
        Write-Host "Collecting system events (NDIS/Storport/USB/WHEA)..." -ForegroundColor Yellow
        try {
            $events = Get-WinEvent -LogName System -MaxEvents 500 -ErrorAction Stop |
                Where-Object { $_.ProviderName -and ($_.ProviderName -match 'NDIS|storport|USB|WHEA') } |
                Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message
            Save-Csv $events (Join-Path $Folder "system-events.csv")
        } catch {
            Write-Host "Failed to collect system events: $_" -ForegroundColor DarkYellow
        }
    }

    if ($CollectSecurityState) {
        Write-Host "Collecting security & hypervisor state..." -ForegroundColor Yellow
        try {
            $dg = Get-CimInstance -ClassName Win32_DeviceGuard -ErrorAction Stop
            $dgRow = [pscustomobject]@{
                SecurityServicesConfigured = ($dg.SecurityServicesConfigured -join ',')
                SecurityServicesRunning   = ($dg.SecurityServicesRunning -join ',')
            }
            Save-Csv @($dgRow) (Join-Path $Folder "deviceguard.csv")
        } catch {
            Write-Host "Failed to collect DeviceGuard: $_" -ForegroundColor DarkYellow
        }
        try {
            $hvLine = (bcdedit | Select-String -Pattern 'hypervisorlaunchtype').ToString()
            $hvRow = [pscustomobject]@{ Key = 'hypervisorlaunchtype'; Value = $hvLine }
            Save-Csv @($hvRow) (Join-Path $Folder "hypervisor.csv")
        } catch {
            Write-Host "Failed to query hypervisorlaunchtype: $_" -ForegroundColor DarkYellow
        }
    }

    if ($CollectProcessIO) {
        Write-Host "Collecting process IO and network top-talkers..." -ForegroundColor Yellow
        try {
            $procs = Get-Process | Select-Object Name, Id, IOReadBytes, IOWriteBytes
            Save-Csv $procs (Join-Path $Folder "process-io.csv")
        } catch {
            Write-Host "Failed to collect process IO: $_" -ForegroundColor DarkYellow
        }
        try {
            $conns = Get-NetTCPConnection -ErrorAction Stop
            $group = $conns | Group-Object OwningProcess | Sort-Object Count -Descending
            $map = @{}
            foreach ($p in Get-Process) { $map[$p.Id] = $p.Name }
            $rows = @()
            foreach ($g in $group) {
                $name = $map.ContainsKey($g.Name) ? $map[$g.Name] : ''
                $rows += [pscustomobject]@{ OwningProcess = $g.Name; ProcessName = $name; ConnectionCount = $g.Count }
            }
            Save-Csv $rows (Join-Path $Folder "net-top-talkers.csv")
        } catch {
            Write-Host "Failed to collect network top talkers: $_" -ForegroundColor DarkYellow
        }
    }

    $summaryText = @"
Snapshot created at: $(Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
Folder: $Folder

Generated files:
- drivers.csv
- cpu.csv
- interrupts.csv
- usb.csv
- network.csv
- pci.csv
- network-advanced.csv (optional)
- network-rss.csv (optional)
- disk.csv (optional)
- services.csv (optional)
- extra-counters.csv (optional)
- summary.txt
"@
    $summaryPath = Join-Path $Folder "summary.txt"
    $summaryText | Out-File -Encoding UTF8 $summaryPath
}

function Compare-SystemSnapshots {
    param(
        [Parameter(Mandatory=$true)][string]$OldSnapshotPath,
        [Parameter(Mandatory=$true)][string]$NewSnapshotPath,
        [Parameter()][string]$OutDir = "."
    )

    if (-not (Test-Path $OldSnapshotPath)) { throw "OldSnapshotPath does not exist: $OldSnapshotPath" }
    if (-not (Test-Path $NewSnapshotPath)) { throw "NewSnapshotPath does not exist: $NewSnapshotPath" }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $compareFolder = Join-Path $OutDir "compare-$(Split-Path $OldSnapshotPath -Leaf)_vs_$(Split-Path $NewSnapshotPath -Leaf)_$timestamp"
    New-Item -ItemType Directory -Force -Path $compareFolder | Out-Null

    Write-Host "Generating comparison at: $compareFolder" -ForegroundColor Cyan

    function Save-CmpCsv($data, $name) {
        $path = Join-Path $compareFolder $name
        if (-not $data) { $data = @() }
        $data | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $path
        Write-Host " ✓ $name" -ForegroundColor Green
    }

    function Compare-ObjectsByKey {
        param(
            [Parameter(Mandatory = $true)] $Old,
            [Parameter(Mandatory = $true)] $New,
            [string[]]$KeyProps,
            [string[]]$ValueProps,
            [string]$Label
        )

        $results = New-Object System.Collections.Generic.List[object]

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
            if ($oldIndex.ContainsKey($k)) { $oldObj = $oldIndex[$k] }
            if ($newIndex.ContainsKey($k)) { $newObj = $newIndex[$k] }

            $changeType = $null
            if ($oldObj -and -not $newObj) {
                $changeType = "Removed"
            } elseif (-not $oldObj -and $newObj) {
                $changeType = "Added"
            } else {
                $changed = $false
                foreach ($p in $ValueProps) {
                    $oldVal = $oldObj.$p
                    $newVal = $newObj.$p
                    if ("$oldVal" -ne "$newVal") { $changed = $true; break }
                }
                $changeType = $changed ? "Changed" : "Unchanged"
                if (-not $changed) { continue }
            }

            $out = [ordered]@{ Category = $Label; ChangeType = $changeType }

            if ($oldObj) { foreach ($p in $KeyProps) { $out["Key_$p"] = $oldObj.$p } }
            elseif ($newObj) { foreach ($p in $KeyProps) { $out["Key_$p"] = $newObj.$p } }

            foreach ($p in $ValueProps) {
                $out["Old_$p"] = $oldObj ? $oldObj.$p : $null
                $out["New_$p"] = $newObj ? $newObj.$p : $null
            }

            $results.Add([pscustomobject]$out) | Out-Null
        }
        return $results
    }

    $summary = New-Object System.Collections.Generic.List[object]
    function Add-Summary { param([string]$Label, $Diff)
        if (-not $Diff) {
            $summary.Add([pscustomobject]@{ Category=$Label; Added=0; Removed=0; Changed=0 }) | Out-Null; return
        }
        $added   = ($Diff | Where-Object { $_.ChangeType -eq "Added"   }).Count
        $removed = ($Diff | Where-Object { $_.ChangeType -eq "Removed" }).Count
        $changed = ($Diff | Where-Object { $_.ChangeType -eq "Changed" }).Count
        $summary.Add([pscustomobject]@{ Category=$Label; Added=$added; Removed=$removed; Changed=$changed }) | Out-Null
    }

    $oldDriversPath = Join-Path $OldSnapshotPath "drivers.csv"
    $newDriversPath = Join-Path $NewSnapshotPath "drivers.csv"
    if ((Test-Path $oldDriversPath) -and (Test-Path $newDriversPath)) {
        Write-Host "Comparing drivers..." -ForegroundColor Yellow
        $oldDrivers = Import-Csv $oldDriversPath
        $newDrivers = Import-Csv $newDriversPath
        $driversDiff = Compare-ObjectsByKey -Old $oldDrivers -New $newDrivers -KeyProps @("DeviceID","Driver") -ValueProps @("DriverVersion","DriverDate","DriverProviderName","Path") -Label "Drivers"
        Save-CmpCsv $driversDiff "drivers-diff.csv"
        Add-Summary -Label "Drivers" -Diff $driversDiff
    }

    $oldIntPath = Join-Path $OldSnapshotPath "interrupts.csv"
    $newIntPath = Join-Path $NewSnapshotPath "interrupts.csv"
    if ((Test-Path $oldIntPath) -and (Test-Path $newIntPath)) {
        Write-Host "Comparing interrupts/DPC..." -ForegroundColor Yellow
        $oldInt = Import-Csv $oldIntPath
        $newInt = Import-Csv $newIntPath
        $intDiff = Compare-ObjectsByKey -Old $oldInt -New $newInt -KeyProps @("Path") -ValueProps @("CookedValue") -Label "Interrupts"
        Save-CmpCsv $intDiff "interrupts-diff.csv"
        Add-Summary -Label "Interrupts/DPC" -Diff $intDiff
    }

    $oldCpuPath = Join-Path $OldSnapshotPath "cpu.csv"
    $newCpuPath = Join-Path $NewSnapshotPath "cpu.csv"
    if ((Test-Path $oldCpuPath) -and (Test-Path $newCpuPath)) {
        Write-Host "Comparing CPU..." -ForegroundColor Yellow
        $oldCpu = Import-Csv $oldCpuPath
        $newCpu = Import-Csv $newCpuPath
        $cpuDiff = Compare-ObjectsByKey -Old $oldCpu -New $newCpu -KeyProps @("Path") -ValueProps @("CookedValue") -Label "CPU"
        Save-CmpCsv $cpuDiff "cpu-diff.csv"
        Add-Summary -Label "CPU" -Diff $cpuDiff
    }

    $oldUsbPath = Join-Path $OldSnapshotPath "usb.csv"
    $newUsbPath = Join-Path $NewSnapshotPath "usb.csv"
    if ((Test-Path $oldUsbPath) -and (Test-Path $newUsbPath)) {
        Write-Host "Comparing USB..." -ForegroundColor Yellow
        $oldUsb = Import-Csv $oldUsbPath
        $newUsb = Import-Csv $newUsbPath
        $usbDiff = Compare-ObjectsByKey -Old $oldUsb -New $newUsb -KeyProps @("InstanceId") -ValueProps @("Status","FriendlyName") -Label "USB"
        Save-CmpCsv $usbDiff "usb-diff.csv"
        Add-Summary -Label "USB" -Diff $usbDiff
    }

    $oldNetPath = Join-Path $OldSnapshotPath "network.csv"
    $newNetPath = Join-Path $NewSnapshotPath "network.csv"
    if ((Test-Path $oldNetPath) -and (Test-Path $newNetPath)) {
        Write-Host "Comparing Network..." -ForegroundColor Yellow
        $oldNet = Import-Csv $oldNetPath
        $newNet = Import-Csv $newNetPath
        $netDiff = Compare-ObjectsByKey -Old $oldNet -New $newNet -KeyProps @("Name") -ValueProps @("Status","InterfaceDescription","DriverInformation") -Label "Network"
        Save-CmpCsv $netDiff "network-diff.csv"
        Add-Summary -Label "Network" -Diff $netDiff
    }

    $oldPciPath = Join-Path $OldSnapshotPath "pci.csv"
    $newPciPath = Join-Path $NewSnapshotPath "pci.csv"
    if ((Test-Path $oldPciPath) -and (Test-Path $newPciPath)) {
        Write-Host "Comparing PCI..." -ForegroundColor Yellow

    $oldNetAdvPath = Join-Path $OldSnapshotPath "network-advanced.csv"
    $newNetAdvPath = Join-Path $NewSnapshotPath "network-advanced.csv"
    if ((Test-Path $oldNetAdvPath) -and (Test-Path $newNetAdvPath)) {
        Write-Host "Comparing Network Advanced..." -ForegroundColor Yellow
        $oldNetAdv = Import-Csv $oldNetAdvPath
        $newNetAdv = Import-Csv $newNetAdvPath
        $netAdvDiff = Compare-ObjectsByKey -Old $oldNetAdv -New $newNetAdv -KeyProps @("Name","RegistryKeyword") -ValueProps @("DisplayValue","RegistryValue") -Label "NetworkAdvanced"
        Save-CmpCsv $netAdvDiff "network-advanced-diff.csv"
        Add-Summary -Label "NetworkAdvanced" -Diff $netAdvDiff
    }

    $oldNetRssPath = Join-Path $OldSnapshotPath "network-rss.csv"
    $newNetRssPath = Join-Path $NewSnapshotPath "network-rss.csv"
    if ((Test-Path $oldNetRssPath) -and (Test-Path $newNetRssPath)) {
        Write-Host "Comparing Network RSS..." -ForegroundColor Yellow
        $oldNetRss = Import-Csv $oldNetRssPath
        $newNetRss = Import-Csv $newNetRssPath
        $netRssDiff = Compare-ObjectsByKey -Old $oldNetRss -New $newNetRss -KeyProps @("Name") -ValueProps @("Enabled","Profile","NumberOfReceiveQueues","BaseProcessorGroup","BaseProcessorNumber","MaxProcessorNumber") -Label "NetworkRSS"
        Save-CmpCsv $netRssDiff "network-rss-diff.csv"
        Add-Summary -Label "NetworkRSS" -Diff $netRssDiff
    }

    $oldDiskPath = Join-Path $OldSnapshotPath "disk.csv"
    $newDiskPath = Join-Path $NewSnapshotPath "disk.csv"
    if ((Test-Path $oldDiskPath) -and (Test-Path $newDiskPath)) {
        Write-Host "Comparing Disks..." -ForegroundColor Yellow
        $oldDisk = Import-Csv $oldDiskPath
        $newDisk = Import-Csv $newDiskPath
        $diskDiff = Compare-ObjectsByKey -Old $oldDisk -New $newDisk -KeyProps @("FriendlyName","SerialNumber") -ValueProps @("MediaType","BusType","HealthStatus","OperationalStatus","FirmwareVersion","Size") -Label "Disk"
        Save-CmpCsv $diskDiff "disk-diff.csv"
        Add-Summary -Label "Disk" -Diff $diskDiff
    }

    $oldSvcPath = Join-Path $OldSnapshotPath "services.csv"
    $newSvcPath = Join-Path $NewSnapshotPath "services.csv"
    if ((Test-Path $oldSvcPath) -and (Test-Path $newSvcPath)) {
        Write-Host "Comparing Services..." -ForegroundColor Yellow
        $oldSvc = Import-Csv $oldSvcPath
        $newSvc = Import-Csv $newSvcPath
        $svcDiff = Compare-ObjectsByKey -Old $oldSvc -New $newSvc -KeyProps @("Name") -ValueProps @("Status","StartType","DisplayName") -Label "Services"
        Save-CmpCsv $svcDiff "services-diff.csv"
        Add-Summary -Label "Services" -Diff $svcDiff
    }

    $oldExtraPath = Join-Path $OldSnapshotPath "extra-counters.csv"
    $newExtraPath = Join-Path $NewSnapshotPath "extra-counters.csv"
        $oldNetStatsPath = Join-Path $OldSnapshotPath "network-stats.csv"
        $newNetStatsPath = Join-Path $NewSnapshotPath "network-stats.csv"
        if ((Test-Path $oldNetStatsPath) -and (Test-Path $newNetStatsPath)) {
            Write-Host "Comparing Network Stats..." -ForegroundColor Yellow
            $oldNetStats = Import-Csv $oldNetStatsPath
            $newNetStats = Import-Csv $newNetStatsPath
            $netStatsDiff = Compare-ObjectsByKey -Old $oldNetStats -New $newNetStats -KeyProps @("Name") -ValueProps @("ReceivedBytes","SentBytes","ReceivedUnicastPackets","SentUnicastPackets") -Label "NetworkStats"
            Save-CmpCsv $netStatsDiff "network-stats-diff.csv"
            Add-Summary -Label "NetworkStats" -Diff $netStatsDiff
        }

        $oldEventsPath = Join-Path $OldSnapshotPath "system-events.csv"
        $newEventsPath = Join-Path $NewSnapshotPath "system-events.csv"
        if ((Test-Path $oldEventsPath) -and (Test-Path $newEventsPath)) {
            Write-Host "Comparing System Events..." -ForegroundColor Yellow
            $oldEvents = Import-Csv $oldEventsPath
            $newEvents = Import-Csv $newEventsPath
            $eventsDiff = Compare-ObjectsByKey -Old $oldEvents -New $newEvents -KeyProps @("TimeCreated","ProviderName","Id") -ValueProps @("LevelDisplayName") -Label "SystemEvents"
            Save-CmpCsv $eventsDiff "system-events-diff.csv"
            Add-Summary -Label "SystemEvents" -Diff $eventsDiff
        }

        $oldDGPath = Join-Path $OldSnapshotPath "deviceguard.csv"
        $newDGPath = Join-Path $NewSnapshotPath "deviceguard.csv"
        if ((Test-Path $oldDGPath) -and (Test-Path $newDGPath)) {
            Write-Host "Comparing DeviceGuard..." -ForegroundColor Yellow
            $oldDG = Import-Csv $oldDGPath
            $newDG = Import-Csv $newDGPath
            $dgDiff = Compare-ObjectsByKey -Old $oldDG -New $newDG -KeyProps @("SecurityServicesConfigured","SecurityServicesRunning") -ValueProps @() -Label "DeviceGuard"
            Save-CmpCsv $dgDiff "deviceguard-diff.csv"
            Add-Summary -Label "DeviceGuard" -Diff $dgDiff
        }

        $oldHvPath = Join-Path $OldSnapshotPath "hypervisor.csv"
        $newHvPath = Join-Path $NewSnapshotPath "hypervisor.csv"
        if ((Test-Path $oldHvPath) -and (Test-Path $newHvPath)) {
            Write-Host "Comparing Hypervisor State..." -ForegroundColor Yellow
            $oldHv = Import-Csv $oldHvPath
            $newHv = Import-Csv $newHvPath
            $hvDiff = Compare-ObjectsByKey -Old $oldHv -New $newHv -KeyProps @("Key") -ValueProps @("Value") -Label "Hypervisor"
            Save-CmpCsv $hvDiff "hypervisor-diff.csv"
            Add-Summary -Label "Hypervisor" -Diff $hvDiff
        }

        $oldTopTalkersPath = Join-Path $OldSnapshotPath "net-top-talkers.csv"
        $newTopTalkersPath = Join-Path $NewSnapshotPath "net-top-talkers.csv"
        if ((Test-Path $oldTopTalkersPath) -and (Test-Path $newTopTalkersPath)) {
            Write-Host "Comparing Network Top Talkers..." -ForegroundColor Yellow
            $oldTT = Import-Csv $oldTopTalkersPath
            $newTT = Import-Csv $newTopTalkersPath
            $ttDiff = Compare-ObjectsByKey -Old $oldTT -New $newTT -KeyProps @("OwningProcess") -ValueProps @("ConnectionCount","ProcessName") -Label "NetTopTalkers"
            Save-CmpCsv $ttDiff "net-top-talkers-diff.csv"
            Add-Summary -Label "NetTopTalkers" -Diff $ttDiff
        }

        $oldProcIoPath = Join-Path $OldSnapshotPath "process-io.csv"
        $newProcIoPath = Join-Path $NewSnapshotPath "process-io.csv"
        if ((Test-Path $oldProcIoPath) -and (Test-Path $newProcIoPath)) {
            Write-Host "Comparing Process IO..." -ForegroundColor Yellow
            $oldPIO = Import-Csv $oldProcIoPath
            $newPIO = Import-Csv $newProcIoPath
            $pioDiff = Compare-ObjectsByKey -Old $oldPIO -New $newPIO -KeyProps @("Id","Name") -ValueProps @("IOReadBytes","IOWriteBytes") -Label "ProcessIO"
            Save-CmpCsv $pioDiff "process-io-diff.csv"
            Add-Summary -Label "ProcessIO" -Diff $pioDiff
        }
    if ((Test-Path $oldExtraPath) -and (Test-Path $newExtraPath)) {
        Write-Host "Comparing Extra Counters..." -ForegroundColor Yellow
        $oldExtra = Import-Csv $oldExtraPath
        $newExtra = Import-Csv $newExtraPath
        $extraDiff = Compare-ObjectsByKey -Old $oldExtra -New $newExtra -KeyProps @("Path") -ValueProps @("CookedValue") -Label "ExtraCounters"
        Save-CmpCsv $extraDiff "extra-counters-diff.csv"
        Add-Summary -Label "ExtraCounters" -Diff $extraDiff
    }
        $oldPci = Import-Csv $oldPciPath
        $newPci = Import-Csv $newPciPath
        $pciDiff = Compare-ObjectsByKey -Old $oldPci -New $newPci -KeyProps @("InstanceId") -ValueProps @("Status","FriendlyName","Class") -Label "PCI"
        Save-CmpCsv $pciDiff "pci-diff.csv"
        Add-Summary -Label "PCI" -Diff $pciDiff
    }

    $summaryPath = Join-Path $compareFolder "summary.csv"
    $summary | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $summaryPath

    return $compareFolder
}

function Build-AnalysisJson {
    param(
        [Parameter(Mandatory=$true)][string]$CompareFolder,
        [Parameter(Mandatory=$true)][string]$SnapshotAPath,
        [Parameter(Mandatory=$true)][string]$SnapshotBPath,
        [string]$LabelA = "before",
        [string]$LabelB = "after"
    )

    $jsonOut = Join-Path $CompareFolder "analysis_for_llm.json"

    function LoadOrNull($path) { if (Test-Path $path) { Import-Csv $path } else { $null } }

    $driversDiff     = LoadOrNull (Join-Path $CompareFolder "drivers-diff.csv")
    $usbDiff         = LoadOrNull (Join-Path $CompareFolder "usb-diff.csv")
    $pciDiff         = LoadOrNull (Join-Path $CompareFolder "pci-diff.csv")
    $netDiff         = LoadOrNull (Join-Path $CompareFolder "network-diff.csv")
    $cpuDiff         = LoadOrNull (Join-Path $CompareFolder "cpu-diff.csv")
    $interruptsDiff  = LoadOrNull (Join-Path $CompareFolder "interrupts-diff.csv")
    $summaryCsv      = LoadOrNull (Join-Path $CompareFolder "summary.csv")
    $netAdvDiff      = LoadOrNull (Join-Path $CompareFolder "network-advanced-diff.csv")
    $netRssDiff      = LoadOrNull (Join-Path $CompareFolder "network-rss-diff.csv")
    $diskDiff        = LoadOrNull (Join-Path $CompareFolder "disk-diff.csv")
    $servicesDiff    = LoadOrNull (Join-Path $CompareFolder "services-diff.csv")
    $extraCountersDiff = LoadOrNull (Join-Path $CompareFolder "extra-counters-diff.csv")
    $netStatsDiff    = LoadOrNull (Join-Path $CompareFolder "network-stats-diff.csv")
    $eventsDiff      = LoadOrNull (Join-Path $CompareFolder "system-events-diff.csv")
    $deviceGuardDiff = LoadOrNull (Join-Path $CompareFolder "deviceguard-diff.csv")
    $hypervisorDiff  = LoadOrNull (Join-Path $CompareFolder "hypervisor-diff.csv")
    $topTalkersDiff  = LoadOrNull (Join-Path $CompareFolder "net-top-talkers-diff.csv")
    $processIoDiff   = LoadOrNull (Join-Path $CompareFolder "process-io-diff.csv")

    $suspectDrivers = @()
    if ($driversDiff) {
        $suspectDrivers = $driversDiff | Where-Object { $_.ChangeType -ne "Unchanged" } |
            Select-Object @{n='deviceId';e={$_.Key_DeviceID}},
                          @{n='driverName';e={$_.Key_Driver}},
                          @{n='oldVersion';e={$_.Old_DriverVersion}},
                          @{n='newVersion';e={$_.New_DriverVersion}},
                          @{n='oldProvider';e={$_.Old_DriverProviderName}},
                          @{n='newProvider';e={$_.New_DriverProviderName}},
                          @{n='oldPath';e={$_.Old_Path}},
                          @{n='newPath';e={$_.New_Path}},
                          @{n='changeType';e={$_.ChangeType}}
    }

    $spikes = @()
    if ($interruptsDiff) {
        foreach ($row in $interruptsDiff) {
            $oldVal = [double]($row.Old_CookedValue)
            $newVal = [double]($row.New_CookedValue)
            $delta  = $newVal - $oldVal
            if ($delta -gt 0) {
                $severity = if ($delta -ge 1000) { "high" } elseif ($delta -ge 100) { "medium" } else { "low" }
                $spikes += [pscustomobject]@{ path=$row.Key_Path; old=$oldVal; new=$newVal; delta=$delta; severity=$severity }
            }
        }
        $spikes = $spikes | Sort-Object -Property delta -Descending
    }

    function ParseCoreFromPath($path) {
        if (-not $path) { return $null }
        $m = [regex]::Match($path, "processor\((?<core>\d+)\)")
        if ($m.Success) { return [int]$m.Groups['core'].Value } else { return $null }
    }

    function ParseCpuInfoCore($path) {
        if (-not $path) { return $null }
        $m = [regex]::Match($path, "processor information\(0,(?<core>\d+)\)")
        if ($m.Success) { return [int]$m.Groups['core'].Value } else { return $null }
    }

    $coreAnalysis = @()
    if ($interruptsDiff -or $cpuDiff) {
        $coreMap = @{}
        if ($interruptsDiff) {
            foreach ($row in $interruptsDiff) {
                $core = ParseCoreFromPath($row.Key_Path)
                if ($null -ne $core) {
                    if (-not $coreMap.ContainsKey($core)) { $coreMap[$core] = @{} }
                    if ($row.Key_Path -like "*interrupts/sec") {
                        $coreMap[$core]['int_old'] = [double]$row.Old_CookedValue
                        $coreMap[$core]['int_new'] = [double]$row.New_CookedValue
                    } elseif ($row.Key_Path -like "*% dpc time") {
                        $coreMap[$core]['dpc_old'] = [double]$row.Old_CookedValue
                        $coreMap[$core]['dpc_new'] = [double]$row.New_CookedValue
                    } elseif ($row.Key_Path -like "*dpc rate") {
                        $coreMap[$core]['dpcrate_old'] = [double]$row.Old_CookedValue
                        $coreMap[$core]['dpcrate_new'] = [double]$row.New_CookedValue
                    }
                }
            }
        }
        if ($cpuDiff) {
            foreach ($row in $cpuDiff) {
                $core = ParseCpuInfoCore($row.Key_Path)
                if ($null -ne $core) {
                    if (-not $coreMap.ContainsKey($core)) { $coreMap[$core] = @{} }
                    if ($row.Key_Path -like "*% privileged time") {
                        $coreMap[$core]['priv_old'] = [double]$row.Old_CookedValue
                        $coreMap[$core]['priv_new'] = [double]$row.New_CookedValue
                    }
                }
            }
        }
        foreach ($k in $coreMap.Keys | Sort-Object) {
            $v = $coreMap[$k]
            $coreAnalysis += [pscustomobject]@{
                core = $k
                interrupts_delta = ([double]($v['int_new'] -as [double]) - [double]($v['int_old'] -as [double]))
                dpc_time_delta = ([double]($v['dpc_new'] -as [double]) - [double]($v['dpc_old'] -as [double]))
                dpc_rate_delta = ([double]($v['dpcrate_new'] -as [double]) - [double]($v['dpcrate_old'] -as [double]))
                privileged_time_delta = ([double]($v['priv_new'] -as [double]) - [double]($v['priv_old'] -as [double]))
            }
        }
    }

    $redistributionEvents = @()
    if ($interruptsDiff) {
        $inc = $coreAnalysis | Where-Object { $_.interrupts_delta -gt 100 }
        $dec = $coreAnalysis | Where-Object { $_.interrupts_delta -lt -100 }
        $totalChange = 0
        foreach ($row in ($interruptsDiff | Where-Object { $_.Key_Path -like "*\\processor(_total)\\interrupts/sec" })) {
            $totalChange = [double]$row.New_CookedValue - [double]$row.Old_CookedValue
        }
        if (($inc.Count -ge 2) -and ($dec.Count -ge 4)) {
            $redistributionEvents += [pscustomobject]@{
                type = "interrupt_redistribution"
                summary = "Interrupt load moved from several cores to few cores"
                total_interrupts_delta = $totalChange
                top_increasers = ($inc | Sort-Object interrupts_delta -Descending | Select-Object -First 5)
                top_decreasers = ($dec | Sort-Object interrupts_delta | Select-Object -First 5)
            }
        }
    }

    function ExtractChanges($diff, $keyName, $fields) {
        if (-not $diff) { return @() }
        return ($diff | Where-Object { $_.ChangeType -ne "Unchanged" } | ForEach-Object {
            $obj = [ordered]@{ changeType = $_.ChangeType; key = $_.("Key_" + $keyName) }
            foreach ($f in $fields) {
                $obj["old_" + $f] = $_.("Old_" + $f)
                $obj["new_" + $f] = $_.("New_" + $f)
            }
            [pscustomobject]$obj
        })
    }

    $usbChanges = ExtractChanges $usbDiff "InstanceId" @("Status","FriendlyName")
    $pciChanges = ExtractChanges $pciDiff "InstanceId" @("Status","FriendlyName","Class")
    $netChanges = ExtractChanges $netDiff "Name" @("Status","InterfaceDescription","DriverInformation")

    $cpuChanges = @()
    if ($cpuDiff) {
        $cpuChanges = $cpuDiff | ForEach-Object {
            [pscustomobject]@{ path=$_.Key_Path; old=[double]$_.Old_CookedValue; new=[double]$_.New_CookedValue; delta=([double]$_.New_CookedValue - [double]$_.Old_CookedValue) }
        } | Sort-Object -Property delta -Descending
    }

    $causal = @()
    foreach ($u in $usbChanges) {
        $matchingSpikes = $spikes | Where-Object { $_.path -match "DPC Rate|% DPC Time|Interrupts/sec" }
        if ($matchingSpikes) {
            $causal += [pscustomobject]@{
                category = "USB"
                key = $u.key
                relation = "USB device state change correlates with DPC/ISR increase"
                evidence = $matchingSpikes | Select-Object -First 3
                severity = "medium"
            }
        }
    }

    $result = [ordered]@{
        meta = [ordered]@{
            labelA = $LabelA
            labelB = $LabelB
            snapshotA = $SnapshotAPath
            snapshotB = $SnapshotBPath
            compareFolder = $CompareFolder
            generatedAt = (Get-Date).ToString("o")
        }
        summary = $summaryCsv
        primaryChanges = [ordered]@{
            drivers = $driversDiff
            usb = $usbDiff
            pci = $pciDiff
            network = $netDiff
            cpu = $cpuDiff
            interrupts = $interruptsDiff
            networkAdvanced = $netAdvDiff
            networkRss = $netRssDiff
            disk = $diskDiff
            services = $servicesDiff
            extraCounters = $extraCountersDiff
            networkStats = $netStatsDiff
            systemEvents = $eventsDiff
            deviceGuard = $deviceGuardDiff
            hypervisor = $hypervisorDiff
            netTopTalkers = $topTalkersDiff
            processIO = $processIoDiff
        }
        suspectedDrivers = $suspectDrivers
        isrDpcSpikes = $spikes
        deviceStateChanges = [ordered]@{
            usb = $usbChanges
            pci = $pciChanges
            network = $netChanges
        }
        cpuChanges = $cpuChanges
        coreInterruptAnalysis = $coreAnalysis
        interruptRedistributionEvents = $redistributionEvents
        potentialCausalRelations = $causal
    }

    $result | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonOut -Encoding UTF8
    Write-Host "JSON consolidado em: $jsonOut" -ForegroundColor Cyan
    return $jsonOut
}

function MaybeRunWprTrace {
    param([string]$DurationSeconds, [string]$Label, [string]$OutDir)
    $wpr = "$env:SystemRoot\System32\wpr.exe"
    if (-not (Test-Path $wpr)) { Write-Host "wpr.exe not found (optional ADK/WPT)." -ForegroundColor DarkYellow; return $null }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outFile = Join-Path $OutDir "DPC-ISR-$Label-$timestamp.etl"
    Write-Host "Starting WPR dpcisr $DurationSeconds s -> $outFile" -ForegroundColor Yellow
    & $wpr -start dpcisr -filemode | Out-Null
    Start-Sleep -Seconds $DurationSeconds
    & $wpr -stop $outFile | Out-Null
    return $outFile
}

$root = $OutRoot
if (-not (Test-Path $root)) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
$root = Resolve-Path $root

# Create run timestamp folder under analysis root: ./analysis/[datetime]/
$runStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$runRoot = Join-Path $root $runStamp
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

$folderA = New-StampFolder $runRoot "snapshot-$LabelA"
$folderB = New-StampFolder $runRoot "snapshot-$LabelB"

if ($IncludeWprTrace) { MaybeRunWprTrace -DurationSeconds $WprDurationSeconds -Label $LabelA -OutDir $folderA | Out-Null }
New-SystemSnapshot -Folder $folderA

Write-Host "Perform your action between snapshots (e.g., start Docker, reproduce issue)." -ForegroundColor DarkGray
if ($InteractivePause) {
    Read-Host "Press ENTER when ready to start snapshot '$LabelB'" | Out-Null
} elseif ($PauseSeconds -gt 0) {
    Write-Host "Pausing for $PauseSeconds second(s) before snapshot '$LabelB'..." -ForegroundColor Yellow
    Start-Sleep -Seconds $PauseSeconds
}

if ($IncludeWprTrace) { MaybeRunWprTrace -DurationSeconds $WprDurationSeconds -Label $LabelB -OutDir $folderB | Out-Null }
New-SystemSnapshot -Folder $folderB

$compareFolder = Compare-SystemSnapshots -OldSnapshotPath $folderA -NewSnapshotPath $folderB -OutDir $runRoot
$finalJson = Build-AnalysisJson -CompareFolder $compareFolder -SnapshotAPath $folderA -SnapshotBPath $folderB -LabelA $LabelA -LabelB $LabelB

Write-Host "Done. Artifacts at:" -ForegroundColor Cyan
Write-Host " - $folderA" -ForegroundColor Cyan
Write-Host " - $folderB" -ForegroundColor Cyan
Write-Host " - $compareFolder" -ForegroundColor Cyan
Write-Host " - $finalJson" -ForegroundColor Cyan