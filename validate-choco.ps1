
# Verificar se o Chocolatey está instalado
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Chocolatey não encontrado. Instalando Chocolatey..." -ForegroundColor Cyan
    
    . "$PSScriptRoot\validate-admin.ps1"
    
    # Baixar e instalar o Chocolatey
    Set-ExecutionPolicy Bypass -Scope Process -Force; 
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));

    # Verificar se a instalação foi bem-sucedida
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Chocolatey instalado com sucesso." -ForegroundColor Green
    } else {
        Write-Host "Falha na instalação do Chocolatey." -ForegroundColor Red
    }
} else {
    Write-Host "Chocolatey já está instalado." -ForegroundColor Green
}
