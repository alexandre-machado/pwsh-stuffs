param(
    [string]$OutDir = "./snapshot"
)

# ========== PREPARAÇÃO ==========
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$folder = Join-Path $OutDir "snapshot-$timestamp"

New-Item -ItemType Directory -Force -Path $folder | Out-Null
Write-Host "Criando snapshot em: $folder" -ForegroundColor Cyan

# Helper CSV export
function Save-Csv($data, $name) {
    $path = Join-Path $folder $name
    $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-Host " ✓ $name salvo" -ForegroundColor Green
}

# ========== DRIVERS ==========
Write-Host "Coletando drivers carregados..." -ForegroundColor Yellow
$drivers = Get-WmiObject Win32_PnPSignedDriver |
    Select-Object DeviceName, DriverProviderName, DriverVersion, DriverDate,
                  IsSigned, Driver, InfName, Manufacturer, DeviceID, DriverClass, Path
Save-Csv $drivers "drivers.csv"

# ========== CPU ==========
Write-Host "Coletando estado da CPU..." -ForegroundColor Yellow
$cpu = Get-Counter "\Processor Information(*)\Processor Frequency",
                   "\Processor Information(*)\% Processor Time",
                   "\Processor Information(*)\% Privileged Time"
Save-Csv $cpu.CounterSamples "cpu.csv"

# ========== INTERRUPTS & DPC ==========
Write-Host "Coletando ISR/DPC..." -ForegroundColor Yellow
$interrupts = Get-Counter "\Processor(*)\Interrupts/sec",
                          "\Processor(*)\DPC Rate",
                          "\Processor(*)\% DPC Time"
Save-Csv $interrupts.CounterSamples "interrupts.csv"

# ========== USB ==========
Write-Host "Coletando dispositivos USB..." -ForegroundColor Yellow
$usb = Get-PnpDevice -Class USB | Select-Object Status, Class, FriendlyName, InstanceId
Save-Csv $usb "usb.csv"

# ========== REDE ==========
Write-Host "Coletando adaptadores de rede..." -ForegroundColor Yellow
$net = Get-NetAdapter | Select-Object Name, Status, InterfaceDescription, DriverInformation
Save-Csv $net "network.csv"

# ========== PCI ==========
Write-Host "Coletando dispositivos PCI..." -ForegroundColor Yellow
$pci = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "PCI*" } |
        Select-Object Status, Class, FriendlyName, InstanceId
Save-Csv $pci "pci.csv"

# ========== RESUMO ==========
$summaryPath = Join-Path $folder "summary.txt"
@"
Snapshot criado em: $timestamp
Pasta: $folder

Arquivos gerados:
- drivers.csv
- cpu.csv
- interrupts.csv
- usb.csv
- network.csv
- pci.csv
- summary.txt

Use isso para comparar antes/depois do Docker, antes/depois de engasgos,
ou antes/depois de mexer em serviços/drivers/energia.
"@ | Out-File -Encoding UTF8 $summaryPath

Write-Host "`nSnapshot concluído." -ForegroundColor Cyan
Write-Host "Arquivos salvos em: $folder" -ForegroundColor Cyan
