<#
.SYNOPSIS
    Enable the specified node(s).
#>
[cmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LTMName,
    [Parameter(Mandatory)]
    [string]$UserName,
    [Parameter(Mandatory)]
    [string]$Password,
    [Parameter(Mandatory)]
    [string]$Partition,
    [Parameter(Mandatory)]
    [string[]]$Name,
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
    $Name.split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {
        if( ![string]::IsNullOrWhiteSpace($_) -and ![string]::Equals('\n', $_)) {
            $itemname = $_ -replace "[""']","" # Strip single/double quotes
            if (Test-Node -F5Session $session -Name $itemname -Partition $Partition) {
                $items = Get-Node -F5Session $session -Name $itemname -Partition $Partition -ErrorAction SilentlyContinue
                $items | Enable-Node -F5Session $session | Out-Null
                $items | ForEach-Object {
                    Write-Host ('Enabled: {0} ({1})' -f $_.name,$_.address)
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
