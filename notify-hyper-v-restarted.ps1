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

$time = Get-VM WinDev2308Eval | Select-Object -ExpandProperty Uptime
$val = $True

Write-Host "time is: $time"
while ($val -eq $True) {
    if ($time -ge (Get-VM 'WinDev2308Eval' | Select-Object -ExpandProperty Uptime)) {
        Write-Host "uptime: $(Get-VM 'WinDev2308Eval' | Select-Object -ExpandProperty Uptime)"
        send-notify
        # $val = $False
    }
    else {
        Write-Host "uptime: $(Get-VM 'WinDev2308Eval' | Select-Object -ExpandProperty Uptime)"
        # $val = $False
    }
    $time = Get-VM WinDev2308Eval | Select-Object -ExpandProperty Uptime
    Start-Sleep -Seconds 2
}
