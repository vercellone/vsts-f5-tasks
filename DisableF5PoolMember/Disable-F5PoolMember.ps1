<#
.SYNOPSIS
    Disable pool member(s) in the specified pool(s).
#>
[cmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LTMName,
    [Parameter(Mandatory)]
    [string]$UserName,
    [Parameter(Mandatory)]
    [string]$Password,
    [Alias('iApp')]
    [Parameter()]
    [string]$Application='',
    [Parameter(Mandatory)]
    [string]$Partition,
    [Parameter(Mandatory)]
    [string[]]$PoolName,
    [Parameter()]
    [string]$Name,
    [Parameter()]
    [string]$DeviceGroup,
    [string]$Force='false'
)
begin {
    if (!$env:CURRENT_TASK_ROOTDIR) {
        $env:CURRENT_TASK_ROOTDIR = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    Import-Module $env:CURRENT_TASK_ROOTDIR\F5-LTM\F5-LTM.psm1 -Force

    $secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
    $f5creds = New-Object System.Management.Automation.PSCredential ($UserName, $secpasswd)
    $session = New-F5Session -LTMName $LTMName -LTMCredentials $f5creds -PassThrough
}
process {
    $changed = $false
    $PoolName.split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {
        if( ![string]::IsNullOrWhiteSpace($_) -and ![string]::Equals('\n', $_)) {
            $itemname = $_ -replace "[""']","" # Strip single/double quotes
            if (Test-Pool -F5Session $session -PoolName $itemname -Partition $Partition -Application $Application) {
                $items = Get-PoolMember -F5Session $session -PoolName $itemname -Partition $Partition -Application $Application -ErrorAction SilentlyContinue | Where-Object { $Name -eq '*' -or $_.name -match "$Name" }
                $items | Disable-PoolMember -F5Session $session -Force:$([bool]::Parse($Force)) | Out-Null
                $items | ForEach-Object {
                    Write-Host ('Disabled: {0} ({1})' -f $_.GetFullName(),$_.address)
                }
                $changed = [bool]$items
            }
        }
    }
    if ($changed) {
        if ($DeviceGroup) {
            Sync-DeviceToGroup -F5Session $session -GroupName $DeviceGroup | Out-Null
        }
    } else {
        Write-Host "##vso[task.logissue type=warning;] Nothing disabled"
    }
}