# Convert all .sh files from CRLF to LF
Get-ChildItem -Filter '*.sh' -File | ForEach-Object {
    $content = [System.IO.File]::ReadAllText($_.FullName)
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $content, [System.Text.Encoding]::UTF8)
    Write-Host "Fixed: $($_.Name)"
}
