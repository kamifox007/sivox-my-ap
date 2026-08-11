$files = Get-ChildItem -Path "c:\ap_nv\my_app\lib" -Filter "*.dart" -Recurse

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match "\.withOpacity\(") {
        Write-Host "Updating $($file.Name)..."
        $newContent = $content -replace '\.withOpacity\(', '.withValues(alpha: '
        Set-Content -Path $file.FullName -Value $newContent -Encoding utf8
    }
}
