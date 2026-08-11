$files = Get-ChildItem -Path "c:\ap_nv\my_app\lib" -Filter "*.dart" -Recurse

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match "\s+print\(") {
        Write-Host "Cleaning prints in $($file.Name)..."
        $newContent = $content -replace '(?m)^\s*print\(.*?\);', '// print cleaned'
        Set-Content -Path $file.FullName -Value $newContent -Encoding utf8
    }
}
