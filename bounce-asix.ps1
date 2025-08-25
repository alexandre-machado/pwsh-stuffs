<#
reset-usb-hub.ps1
------------------
Script para "reviver" adaptador ASIX que some do barramento USB após hibernação/sleep.

1. Procura por um adaptador ASIX ativo (quando existir).
2. Descobre o dispositivo PnP pai do tipo USB Hub e salva seu InstanceId em cache.
3. Se o ASIX não for encontrado, tenta ler o cache e reinicia o hub pai.
4. Como fallback, executa pnputil /scan-devices para forçar redescoberta.

Requer: privilégios de administrador.
#>

$cacheDir = Join-Path $env:LOCALAPPDATA "BounceAsix"
$cacheFile = Join-Path $cacheDir "parent.id"
if (-not (Test-Path $cacheDir)) { New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null }

function Get-AsixDevice {
    Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -like "*ASIX*" -or $_.InstanceId -like "*VID_0B95*" }
}

function Get-ParentHubId($dev) {
    $parent = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName "DEVPKEY_Device_Parent" -ErrorAction SilentlyContinue
    while ($parent) {
        $p = Get-PnpDevice -InstanceId $parent.Data -ErrorAction SilentlyContinue
        if ($p -and $p.Class -eq "USB" -and $p.FriendlyName -like "*Hub*") {
            return $p.InstanceId
        }
        $parent = Get-PnpDeviceProperty -InstanceId $parent.Data -KeyName "DEVPKEY_Device_Parent" -ErrorAction SilentlyContinue
    }
    return $null
}

try {
    $asix = Get-AsixDevice
    if ($asix) {
        Write-Host "ASIX presente: $($asix.FriendlyName)" -ForegroundColor Green
        $hubId = Get-ParentHubId $asix
        if ($hubId) {
            Set-Content -Path $cacheFile -Value $hubId -Encoding UTF8
            Write-Host "Cache atualizado com HubId: $hubId" -ForegroundColor Cyan
        } else {
            Write-Host "Não consegui identificar o Hub pai." -ForegroundColor Yellow
        }
    } else {
        Write-Host "ASIX não encontrado. Tentando usar cache..." -ForegroundColor Yellow
        if (Test-Path $cacheFile) {
            $hubId = Get-Content $cacheFile -Raw
            if ($hubId) {
                Write-Host "Reiniciando Hub: $hubId" -ForegroundColor Magenta
                Disable-PnpDevice -InstanceId $hubId -Confirm:$false -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                Enable-PnpDevice  -InstanceId $hubId -Confirm:$false -ErrorAction SilentlyContinue
            } else {
                Write-Host "Cache vazio, não há HubId salvo." -ForegroundColor Red
            }
        } else {
            Write-Host "Sem cache salvo. Forçando rescan de dispositivos..." -ForegroundColor DarkYellow
            pnputil /scan-devices | Out-Null
        }
    }
}
catch {
    Write-Error $_
}
