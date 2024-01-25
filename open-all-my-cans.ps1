param(
    [string] $user,
    [string] $pass,
    [string] $Port = 554,
    [string] $Path = "/stream1"
)

# Obtem as infos de rede
$IPInfo = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.InterfaceAlias -eq (Test-NetConnection).InterfaceAlias
    })

# Obtém o endereço IP do computador
$IPAddress = $IPInfo.IPAddress

# Obtém a máscara de sub-rede
$SubnetMask = $IPInfo.PrefixLength

# Calcula o prefixo do IP
$IPPrefix = $IPAddress.Substring(0, $IPAddress.LastIndexOf("."))

# Calcula o intervalo de IPs com base na máscara de sub-rede
$IPRange = switch ($SubnetMask) {
    { $_ -eq 24 } { 1..254 }
    { $_ -eq 25 } { 1..126 }
    { $_ -eq 26 } { 1..62 }
    { $_ -eq 27 } { 1..30 }
    { $_ -eq 28 } { 1..14 }
    { $_ -eq 29 } { 1..6 }
    { $_ -eq 30 } { 1..2 }
    default { 1..254 }
}

Write-Host "[IPAddress]: $IPAddress [SubnetMask]: $SubnetMask [IPPrefix]: $IPPrefix [IPRange length]: $($IPRange.Length)" -ForegroundColor Green

$IPRange | ForEach-Object -Parallel {
    $FullIP = $using:IPPrefix + "." + $_
    $url = "rtsp://" + $using:user + ":" + $using:pass + "@" + $FullIP + $using:Path

    if (Test-NetConnection -ComputerName $FullIP -Port $using:Port -InformationLevel Quiet -WarningAction SilentlyContinue) {
        .$Env:Programfiles\VideoLAN\VLC\vlc.exe $url --zoom=0.5 --loop --qt-minimal-view
    }
} -ThrottleLimit 50
