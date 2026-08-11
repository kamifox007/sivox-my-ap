Get-ChildItem -Path lib -Filter *.dart -Recurse | ForEach-Object {
    $file = $_.FullName
    $content = Get-Content $file
    $content = $content -replace 'SIFO', 'Sivox'
    $content = $content -replace 'sifo', 'sivox'
    Set-Content -Path $file -Value $content
}
