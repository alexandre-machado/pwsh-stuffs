<#
.SYNOPSIS
  Restaura configurações de USB/power para o padrão do Windows.

.PARAMETER ResetPowerPlans
  Se informado, executa também `powercfg /restoredefaultschemes`
  (zera TODOS os planos de energia para os padrões de fábrica).
#>

param(
    [switch]$ResetPowerPlans
)

Write-Host "=== Reset-USB.ps1 ===" -ForegroundColor Cyan

# -----------------------------
# 0. Verificar se é admin
# -----------------------------
$currId = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currId)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Este script precisa ser executado como Administrador." -ForegroundColor Red
    exit 1
}

# -----------------------------
# 1. Preparar pastas e backup
# -----------------------------
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$baseDir   = Join-Path $env:ProgramData "ResetUSB-$timestamp"
New-Item -ItemType Directory -Force -Path $baseDir | Out-Null

$logFile = Join-Path $baseDir "reset-usb.log"
"Reset-USB iniciado em $timestamp" | Out-File -FilePath $logFile -Encoding UTF8

function Log([string]$msg) {
    $line = "$(Get-Date -Format HH:mm:ss)  $msg"
    $line | Tee-Object -FilePath $logFile -Append
}

Log "Backup de chaves de registro relacionadas a USB..."

# Backup básico de chaves de serviço USB
$reg = "$env:SystemRoot\System32\reg.exe"

& $reg export "HKLM\SYSTEM\CurrentControlSet\Services\USB"     (Join-Path $baseDir "USB.reg")     /y 2>$null
& $reg export "HKLM\SYSTEM\CurrentControlSet\Services\USBHUB3" (Join-Path $baseDir "USBHUB3.reg") /y 2>$null
& $reg export "HKLM\SYSTEM\CurrentControlSet\Services\usbhub"  (Join-Path $baseDir "usbhub.reg")  /y 2>$null

Log "Backup de chaves concluído."

# -----------------------------
# 2. Remover Interrupt Management / Affinity Policy de PCI
# -----------------------------
Log "Limpando Interrupt Management/Affinity Policy em dispositivos PCI..."

$pciRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"

if (Test-Path $pciRoot) {
    $keys = Get-ChildItem -Path $pciRoot -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_ -and $_.PSChildName -in @('Interrupt Management','Affinity Policy')
            }

    foreach ($key in $keys) {
        if ($null -eq $key) { continue }

        $path = $key.PSPath
        Log "Removendo: $path"
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Log "Falha ao remover $path : $_"
        }
    }
} else {
    Log "Chave PCI não encontrada em Enum\PCI (estranho, mas prosseguindo)."
}

# -----------------------------
# 3. Restaurar suspensão seletiva de USB (plano atual)
# -----------------------------
Log "Restaurando suspensão seletiva de USB para o plano atual..."

# GUIDs oficiais do subgrupo USB e da configuração de suspensão seletiva
$SUB_USB_GUID          = "2a737441-1930-4402-8d77-b2bebba308a3"
$USB_SELECTIVE_GUID    = "4f971e89-eebd-4455-a8de-9e59040e7347"

# 2 = Enabled (valor padrão)
& powercfg /SETACVALUEINDEX SCHEME_CURRENT $SUB_USB_GUID $USB_SELECTIVE_GUID 2 | Out-Null
& powercfg /SETDCVALUEINDEX SCHEME_CURRENT $SUB_USB_GUID $USB_SELECTIVE_GUID 2 | Out-Null
& powercfg /SETACTIVE      SCHEME_CURRENT                                   | Out-Null

Log "Suspensão seletiva de USB restaurada para 'Ativado' (AC/DC)."

# -----------------------------
# 4. Opcional: reset de TODOS planos
# -----------------------------
if ($ResetPowerPlans) {
    Log "Resetando TODOS os planos de energia com powercfg /restoredefaultschemes..."
    & powercfg /restoredefaultschemes | Out-Null
    Log "Planos de energia restaurados para o padrão de fábrica."
}

# -----------------------------
# 5. Reset suave dos hubs/controladores USB
# -----------------------------
Log "Reset (disable/enable) de hubs e controladores USB..."

Import-Module PnpDevice -ErrorAction SilentlyContinue

# Se o módulo não existir, apenas loga e segue
if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
    Log "Módulo PnpDevice não disponível; pulando reset de hubs."
} else {
    $usbDevices = Get-PnpDevice -PresentOnly -Class USB -ErrorAction SilentlyContinue |
                  Where-Object {
                      $_.FriendlyName -like "*Root Hub*" -or
                      $_.FriendlyName -like "*Generic USB Hub*" -or
                      $_.FriendlyName -like "*eXtensible Host Controller*" -or
                      $_.FriendlyName -like "*USB Host Controller*"
                  }

    foreach ($dev in $usbDevices) {
        Log "Reiniciando dispositivo USB: $($dev.FriendlyName)  ($($dev.InstanceId))"
        try {
            Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Enable-PnpDevice  -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        } catch {
            Log "Falha ao reiniciar $($dev.InstanceId): $_"
        }
    }
}

# -----------------------------
# 6. Finalização
# -----------------------------
Log "Reset-USB concluído. Recomenda-se reiniciar o Windows para garantir recriação de chaves/estado."
Write-Host "`nConcluído. Log em: $logFile" -ForegroundColor Cyan
