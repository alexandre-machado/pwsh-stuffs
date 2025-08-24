<# bounce-asix.ps1 — tries Windows 'sudo' before classic self-elevation
   Purpose: when run without privileges, first tries to relaunch itself via `sudo` (Windows 11)
   and, if not available/fails, uses Start-Process -Verb RunAs (classic self-elevation).
#>

### ----------------------
### 1) Conditional elevation
### ----------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { throw "Could not resolve script path (MyCommand.Path is empty)." }

    $wd = (Get-Location).Path
    $scriptArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$self`""

    # 1a) Tentar 'sudo' do Windows (se existir) para elevar mantendo o diretório
    $sudoCmd = Get-Command sudo -ErrorAction SilentlyContinue
    if ($sudoCmd) {
        try {
            # sudo accepts the full command as argument
            Start-Process -FilePath $sudoCmd.Source -ArgumentList "pwsh $scriptArgs" -WorkingDirectory $wd -WindowStyle Hidden
            exit 0
        } catch {
            Write-Host "Failed to use 'sudo' (Windows). Trying classic self-elevation..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "'sudo' command not found. Proceeding to classic self-elevation..." -ForegroundColor Yellow
    }

    # 1b) Fallback: auto-elevação clássica (pwsh; se não houver, powershell)
    try {
        Start-Process pwsh -Verb RunAs -ArgumentList $scriptArgs -WorkingDirectory $wd -WindowStyle Hidden
    } catch {
        Start-Process powershell -Verb RunAs -ArgumentList $scriptArgs -WorkingDirectory $wd -WindowStyle Hidden
    }
    exit 0
}

### ----------------------
### 2) Main script: "bounce" ASIX adapter after resume
### ----------------------
### Strategy: locate adapters whose Description contains "ASIX" and are not Disabled;
### disable, wait 2s, and re-enable. If none found, script does not fail.

try {
    $ifs = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*ASIX*" -and $_.Status -ne "Disabled" }
} catch {
    Write-Error "Failed to enumerate adapters. Run in Windows PowerShell/PowerShell with networking modules available."
    exit 1
}

if (-not $ifs) {
    Write-Host "No active ASIX adapter found. Nothing to do." -ForegroundColor DarkYellow
    exit 0
}

foreach ($if in $ifs) {
    Write-Host "Restarting adapter: $($if.Name) — $($if.InterfaceDescription)" -ForegroundColor Cyan
    try {
        Disable-NetAdapter -InterfaceDescription $if.InterfaceDescription -Confirm:$false -PassThru | Out-Null
        Start-Sleep -Seconds 2
        Enable-NetAdapter  -InterfaceDescription $if.InterfaceDescription -Confirm:$false -PassThru | Out-Null
        Write-Host "OK: $($if.Name) reactivated." -ForegroundColor Green
    } catch {
        Write-Error "Failed to restart '$($if.Name)': $($_.Exception.Message)"
    }
}

# End
