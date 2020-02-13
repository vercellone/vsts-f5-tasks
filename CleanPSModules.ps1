Get-ChildItem -Path $PSScriptRoot -Directory -Exclude ps_modules | ForEach-Object {
    Remove-Item -Path (Join-Path $_ 'ps_modules') -Force -Recurse
}
