function send-notify {
    Add-Type -AssemblyName System.Windows.Forms 
    $global:balloon = New-Object System.Windows.Forms.NotifyIcon
    $path = (Get-Process -id $pid).Path
    $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path) 
    $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning 
    $balloon.BalloonTipText = 'Hyper-v VM restarted'
    $balloon.BalloonTipTitle = "Hyper-v VM restarted" 
    $balloon.Visible = $true 
    $balloon.ShowBalloonTip(5000)
}

function get-time($name) {
    return Get-VM $name | Select-Object -ExpandProperty Uptime
}

param(
    $name
)

$startTime = get-time $name
$val = $True

Write-Host "time is: $startTime"
while ($val -eq $True) {
    $partialTime = get-time $name
    if ($startTime -ge ($partialTime)) {
        Write-Host "uptime: $($partialTime)"
        send-notify
        # $val = $False
    }
    else {
        Write-Host "uptime: $($partialTime)"
        # $val = $False
    }
    $startTime = $partialTime
    Start-Sleep -Seconds 2
}
