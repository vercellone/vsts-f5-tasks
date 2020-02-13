Get-ChildItem -Path $PSScriptRoot -Directory -Exclude ps_modules | ForEach-Object {
    Copy-Item -Path (Join-Path $PSScriptRoot 'ps_modules') -Destination $_ -Force -Recurse
}
