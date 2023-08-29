-join (
    (48..57) `
    + (97..122) `
    
    | Get-Random -Count 35 | % {[char]$_} `
)