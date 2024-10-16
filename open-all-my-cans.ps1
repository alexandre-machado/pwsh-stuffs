param(
    [string] $user,
    [string] $pass,
    [string] $Port = 554,
    [string] $Path = "/stream1",
    [string] $vlcPath = "$Env:ProgramFiles\VideoLAN\VLC\vlc.exe"
)

if (Test-Path $vlcPath) {
    Write-Host "O VLC está instalado." -ForegroundColor Green
    Write-Host " -> $vlcPath" -ForegroundColor Cyan
} else {
    Write-Host "O VLC não está instalado." -ForegroundColor Red
    exit
}

# Obter as informações de rede
$IPInfo = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -eq (Test-NetConnection).InterfaceAlias
})

# Obter o endereço IP do computador
$IPAddress = $IPInfo.IPAddress
# Obter a máscara de sub-rede
$SubnetMask = $IPInfo.PrefixLength
# Calcular o prefixo do IP
$IPPrefix = $IPAddress.Substring(0, $IPAddress.LastIndexOf("."))

# Calcular o intervalo de IPs com base na máscara de sub-rede
function Get-IPRange {
    param (
        [int] $PrefixLength
    )
    switch ($PrefixLength) {
        24 { 1..254 }
        25 { 1..126 }
        26 { 1..62 }
        27 { 1..30 }
        28 { 1..14 }
        29 { 1..6 }
        30 { 1..2 }
        default { 1..254 }
    }
}

$IPRange = Get-IPRange -PrefixLength $SubnetMask

Write-Host "[IPAddress]: $IPAddress [SubnetMask]: $SubnetMask [IPPrefix]: $IPPrefix [IPRange length]: $($IPRange.Length)" -ForegroundColor Green

$IPRange | ForEach-Object -Parallel {
    $FullIP = $using:IPPrefix + "." + $_
    $url = "rtsp://" + $using:user + ":" + $using:pass + "@" + $FullIP + $using:Path
    $arguments = @($url, "--zoom=0.5", "--loop", "--qt-minimal-view")

    if (Test-NetConnection -ComputerName $FullIP -Port $using:Port -InformationLevel Quiet -WarningAction SilentlyContinue) {
        Write-Host " -> Opening $FullIP : $using:Port" -ForegroundColor Cyan
        Start-Process -FilePath $using:vlcPath -ArgumentList $arguments
    }
} -ThrottleLimit 50
