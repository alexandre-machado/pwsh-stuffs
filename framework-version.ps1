$data = @(
    [pscustomobject]@{Name = '.NET Framework 4.5'; Version = 378389 }
    [pscustomobject]@{Name = '.NET Framework 4.5.1'; Version = 378675 }
    [pscustomobject]@{Name = ".NET Framework 4.5.2"; Version = 379893 }
    [pscustomobject]@{Name = ".NET Framework 4.6"; Version = 393295 }
    [pscustomobject]@{Name = ".NET Framework 4.6.1"; Version = 394254 }
    [pscustomobject]@{Name = ".NET Framework 4.6.2"; Version = 394802 }
    [pscustomobject]@{Name = ".NET Framework 4.7"; Version = 460798 }
    [pscustomobject]@{Name = ".NET Framework 4.7.1"; Version = 461308 }
    [pscustomobject]@{Name = ".NET Framework 4.7.2"; Version = 461808 }
    [pscustomobject]@{Name = ".NET Framework 4.8"; Version = 528040 }
    [pscustomobject]@{Name = ".NET Framework 4.8.1 or later"; Version = 533320 }
) | Sort-Object -Property Version -Descending

$release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release

foreach ($item in $data)
{
  if ($release -ge $item.Version)
  {
    Write-Host $item.Name
    break
  }
}