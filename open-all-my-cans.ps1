param(
    [Parameter(Mandatory)]
    [string] $user,

    [Parameter(Mandatory)]
    [string] $pass,
    [int] $Port = 554,
    [string] $Path = "/stream1",
    [string] $vlcPath = "$Env:ProgramFiles\VideoLAN\VLC\vlc.exe",
    [int] $CacheSize = 10,
    [string] $CachePath = $(Join-Path -Path $PSScriptRoot -ChildPath ".open-all-my-cans.cache.json")
)

function Test-VlcPath {
    param([string] $PathToCheck)
    if (Test-Path $PathToCheck) {
        Write-Host "O VLC esta instalado." -ForegroundColor Green
        Write-Host " -> $PathToCheck" -ForegroundColor Cyan
        return $true
    }

    Write-Host "O VLC nao esta instalado." -ForegroundColor Red
    return $false
}

function Get-LocalIpv4Info {
    $activeInterface = (Test-NetConnection).InterfaceAlias
    return Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.InterfaceAlias -eq $activeInterface
    } | Select-Object -First 1
}

function Get-IpRange {
    param(
        [string] $IPAddress,
        [int] $PrefixLength
    )

    if ($PrefixLength -le 24) {
        return 1..254
    }

    if ($PrefixLength -ge 31) {
        return @()
    }

    [int] $lastOctet = [int]($IPAddress.Split('.')[-1])
    [int] $subnetSize = [Math]::Pow(2, (32 - $PrefixLength))
    [int] $subnetStart = [Math]::Floor($lastOctet / $subnetSize) * $subnetSize
    [int] $firstHost = $subnetStart + 1
    [int] $lastHost = $subnetStart + $subnetSize - 2

    return $firstHost..$lastHost
}

function Read-IpCache {
    param([string] $PathToCache)
    if (-not (Test-Path $PathToCache)) {
        return @()
    }

    try {
        $content = Get-Content -Path $PathToCache -Raw
        $data = $content | ConvertFrom-Json
        if ($null -eq $data -or $null -eq $data.LastIps) {
            return @()
        }
        return @($data.LastIps | Where-Object { $_ -and $_.Trim() -ne "" })
    } catch {
        return @()
    }
}

function Write-IpCache {
    param(
        [string] $PathToCache,
        [string[]] $IpsToSave,
        [int] $MaxItems
    )

    if ($MaxItems -lt 1) {
        return
    }

    $payload = [PSCustomObject]@{
        LastIps = @($IpsToSave | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique | Select-Object -First $MaxItems)
        UpdatedAt = (Get-Date).ToString("s")
    }

    $payload | ConvertTo-Json -Depth 2 | Set-Content -Path $PathToCache -Encoding UTF8
}

if (-not (Test-VlcPath -PathToCheck $vlcPath)) {
    exit
}

$ipInfo = Get-LocalIpv4Info
if ($null -eq $ipInfo) {
    Write-Host "Could not detect a local IPv4 address." -ForegroundColor Red
    exit
}

$ipAddress = $ipInfo.IPAddress
$subnetMask = $ipInfo.PrefixLength
$ipPrefix = $ipAddress.Substring(0, $ipAddress.LastIndexOf("."))
[int[]] $ipRange = @(Get-IpRange -IPAddress $ipAddress -PrefixLength $subnetMask)
[string[]] $cachedIps = @(Read-IpCache -PathToCache $CachePath)

Write-Host "[IPAddress]: $ipAddress [SubnetMask]: $subnetMask [IPPrefix]: $ipPrefix [IPRange length]: $($ipRange.Length)" -ForegroundColor Green

[string[]] $scanIps = @($ipRange | ForEach-Object { "$ipPrefix.$_" })

if ($cachedIps.Count -gt 0) {
    Write-Host "Cache hit(s): $($cachedIps.Count). Trying them first." -ForegroundColor Yellow
}

[string[]] $ipQueue = @(
    $cachedIps
    $scanIps | Where-Object { $_ -notin $cachedIps }
) | Where-Object { $_ }
$foundIps = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

$ipQueue | ForEach-Object -Parallel {
    $fullIp = $_
    $url = "rtsp://" + $using:user + ":" + $using:pass + "@" + $fullIp + ":" + $using:Port + $using:Path
    $arguments = @($url, "--zoom=0.5", "--loop", "--qt-minimal-view")

    if (Test-NetConnection -ComputerName $fullIp -Port $using:Port -InformationLevel Quiet -WarningAction SilentlyContinue) {
        Write-Host " -> Opening $fullIp : $using:Port" -ForegroundColor Cyan
        $foundIpsRef = $using:foundIps
        $null = $foundIpsRef.Add($fullIp)

        # Save cache immediately on each successful connection
        $mutex = [System.Threading.Mutex]::new($false, "Global\OpenAllMyCans_CacheMutex")
        try {
            $null = $mutex.WaitOne()
            $allFound = @($foundIpsRef.ToArray() | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique | Select-Object -First $using:CacheSize)
            $payload = [PSCustomObject]@{
                LastIps   = $allFound
                UpdatedAt = (Get-Date).ToString("s")
            }
            $payload | ConvertTo-Json -Depth 2 | Set-Content -Path $using:CachePath -Encoding UTF8
        }
        finally {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }

        Start-Process -FilePath $using:vlcPath -ArgumentList $arguments
    }
} -ThrottleLimit 50

if ($foundIps.Count -eq 0) {
    Write-Host "No RTSP endpoints found. Check IP range, port, or credentials." -ForegroundColor Yellow
}
