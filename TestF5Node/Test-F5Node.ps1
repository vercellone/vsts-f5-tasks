<#
.SYNOPSIS
    Disable the specified node(s).
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
    [Parameter(Mandatory)]
    [string]$NodeSession,
    [Parameter(Mandatory)]
    [string]$NodeState
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
    $isStateMatch = $true
    $Name.split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {
        if( ![string]::IsNullOrWhiteSpace($_) -and ![string]::Equals('\n', $_)) {
            $itemname = $_ -replace "[""']","" # Strip single/double quotes
            if (Test-Node -F5Session $session -Name $itemname -Partition $Partition) {
                $items = Get-Node -F5Session $session -Name $itemname -Partition $Partition -ErrorAction SilentlyContinue
                $items | ForEach-Object {
                    $statusshape = Get-StatusShape -state $_.state -session $_.session
                    if ($_.session -ne $NodeSession -or $_.state -ne $NodeState) {
                        $isStateMatch = $false
                        Write-Host ('##vso[task.logissue type=warning;] {0} ({1}): session = {2}; state = {3}; f5 status shape = {4}' -f $_.name,$_.address,$_.session,$_.state,$statusshape)
                    } else {
                        Write-Host ('{0} ({1}): session = {2}; state = {3}; f5 status shape = {4}' -f $_.name,$_.address,$_.session,$_.state,$statusshape)
                    }
                }
            }
        }
    }
    if (-not $isStateMatch) {
        $statusshapeExpected = Get-StatusShape -session $NodeSession -state $NodeState
        Write-Host ('##vso[task.logissue type=error;] Test-Node - failed.  Expected all nodes to be session = {0}; state = {1}; f5 status shape = {2}.' -f $NodeSession,$NodeState,$statusshapeExpected)
    }
}