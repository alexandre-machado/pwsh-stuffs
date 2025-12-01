# Check-Hypervisor-Leak.ps1 (v2)

Write-Host "`n=== Checando status de recursos que ativam o Hypervisor ===`n"

function Check-Flag {
    param(
        [string]$Name,
        [bool]$State,
        [string]$Expected   # "On" or "Off"
    )

    if (($Expected -eq "Off" -and $State) -or ($Expected -eq "On" -and -not $State)) {
        Write-Host ("[PROBLEMA] {0} -> Estado: {1}, Esperado: {2}" -f $Name,$State,$Expected) -ForegroundColor Red
    } else {
        Write-Host ("[OK]       {0} -> Estado: {1}" -f $Name,$State) -ForegroundColor Green
    }
}

function Safe-GetFeature($name) {
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
        return $f.State -eq "Enabled"
    } catch {
        # Sem elevação ou feature inexistente -> devolve $false e deixa o log para o usuário
        Write-Host "[AVISO] Falha ao ler feature $name ($_)" -ForegroundColor Yellow
        return $false
    }
}

# 1 — Hyper-V Platform
$hvEnabled   = Safe-GetFeature "Microsoft-Hyper-V-Hypervisor"
Check-Flag "Hyper-V Platform" $hvEnabled "Off"

# 2 — Windows Hypervisor Platform (WHP)
$whpEnabled  = Safe-GetFeature "HypervisorPlatform"
Check-Flag "Windows Hypervisor Platform (WHP)" $whpEnabled "Off"

# 3 — Virtual Machine Platform (necessário para WSL2)
$vmpEnabled  = Safe-GetFeature "VirtualMachinePlatform"
Check-Flag "Virtual Machine Platform (VMP)" $vmpEnabled "On"

# 4 — Windows Sandbox
$sandboxEnabled = Safe-GetFeature "Containers-DisposableClientVM"
Check-Flag "Windows Sandbox" $sandboxEnabled "Off"

# 5 — Application Guard
$appGuardEnabled = Safe-GetFeature "Windows-Defender-ApplicationGuard"
Check-Flag "Application Guard" $appGuardEnabled "Off"

# 6 — Core Isolation / Memory Integrity (HVCI)
$hvciEnabled = $false
try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -ErrorAction Stop
    $hvciEnabled = $dg.SecurityServicesConfigured -contains 1
} catch {
    Write-Host "[AVISO] Win32_DeviceGuard não disponível ($_)" -ForegroundColor Yellow
}
Check-Flag "Memory Integrity / HVCI" $hvciEnabled "Off"

# 7 — Credential Guard
$cgEnabled = $false
try {
    $dgRun = (Get-CimInstance -ClassName Win32_DeviceGuard -ErrorAction Stop).SecurityServicesRunning
    $cgEnabled = $dgRun -contains 2
} catch {
    Write-Host "[AVISO] Credential Guard não detectado ($_)" -ForegroundColor Yellow
}
Check-Flag "Credential Guard" $cgEnabled "Off"

# 8 — Boot configuration: hypervisorlaunchtype
$bcd = (bcdedit /enum) 2>$null | Out-String
if (-not $bcd) {
    Write-Host "[AVISO] Não foi possível ler o bcdedit (talvez sem admin)" -ForegroundColor Yellow
} else {
    if ($bcd -match "hypervisorlaunchtype\s+Auto") {
        Write-Host "[PROBLEMA] hypervisorlaunchtype -> Auto (deve estar Off)" -ForegroundColor Red
    } elseif ($bcd -match "hypervisorlaunchtype\s+Off") {
        Write-Host "[OK]       hypervisorlaunchtype -> Off" -ForegroundColor Green
    } else {
        Write-Host "[PROBLEMA] hypervisorlaunchtype não definido explicitamente -> pode estar usando Auto" -ForegroundColor Red
    }
}

Write-Host "`n=== Diagnóstico completo ===`n"
param(
    [int]$DurationSeconds = 30
)

Write-Host "=== DPC/ISR Trace (WPR) ===" -ForegroundColor Cyan

# Verifica se WPR está disponível
$wpr = "$env:SystemRoot\System32\wpr.exe"
if (-not (Test-Path $wpr)) {
    Write-Host "wpr.exe não encontrado. Instale o Windows Performance Toolkit / ADK." -ForegroundColor Red
    exit 1
}

# Nome do arquivo de saída
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $env:TEMP "DPC-ISR-$timestamp.etl"

Write-Host "Iniciando captura DPC/ISR por $DurationSeconds segundo(s)..." -ForegroundColor Yellow
Write-Host "Arquivo de saída: $outFile" -ForegroundColor Yellow

# Perfil 'dpcisr' é próprio do WPR para latência de drivers
& $wpr -start dpcisr -filemode | Out-Null

Start-Sleep -Seconds $DurationSeconds

Write-Host "Parando captura..." -ForegroundColor Yellow
& $wpr -stop $outFile | Out-Null

Write-Host "Concluído." -ForegroundColor Green
Write-Host "Abra o arquivo no Windows Performance Analyzer (wpa.exe) para ver DPC/ISR por driver." -ForegroundColor Green
Write-Host "Ex.: wpa `"$outFile`""
