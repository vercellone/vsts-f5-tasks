<#
.SYNOPSIS
    Enable pool member(s) in the specified pool(s).
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
    [string]$DeviceGroup
)
begin {
    $secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
    $f5creds = [System.Management.Automation.PSCredential]::new($UserName, $secpasswd)
    $session = New-F5Session -LTMName $LTMName -LTMCredentials $f5creds -PassThrough
}
process {
    $changed = $false
    $PoolName.split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {
        if( ![string]::IsNullOrWhiteSpace($_) -and ![string]::Equals('\n', $_)) {
            $itemname = $_ -replace "[""']","" # Strip single/double quotes
            if (Test-Pool -F5Session $session -PoolName $itemname -Partition $Partition -Application $Application) {
                $items = Get-PoolMember -F5Session $session -PoolName $itemname -Partition $Partition -Application $Application -ErrorAction SilentlyContinue | Where-Object { $Name -eq '*' -or $_.name -match "$Name" }
                $items | Enable-PoolMember -F5Session $session | Out-Null
                $items | ForEach-Object {
                    Write-Host ('Enabled: {0} ({1})' -f $_.GetFullName(),$_.address)
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
