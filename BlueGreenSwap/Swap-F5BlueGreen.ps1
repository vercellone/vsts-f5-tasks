<#
.SYNOPSIS
    Swaps the active pool of a virtual server based on output from a corresponding Select-F5BlueGreen task.
#>
[cmdletBinding()]
param()
begin {
    if (!$env:CURRENT_TASK_ROOTDIR) {
        $env:CURRENT_TASK_ROOTDIR = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    Import-Module $env:CURRENT_TASK_ROOTDIR\F5-LTM\F5-LTM.psm1 -Force
}
process {
    $f5Selections = Get-ChildItem -Path $env:SYSTEM_WORKFOLDER -Filter ('F5BlueGreen-{0}-*.xml' -f $env:Release_ReleaseId)
    if ($f5Selections) {
        $swapcount = 0
        $f5Selections | ForEach-Object {
            try {
                $BlueGreenData = Import-Clixml -Path $_.FullName
                $session = New-F5Session -LTMName $BlueGreenData.LTMName -LTMCredentials $BlueGreenData.Credentials -PassThrough

                $BlueGreenData.VirtualServer.pool = $BlueGreenData.IdlePool.name
                $BlueGreenData.VirtualServer | Set-VirtualServer -F5Session $session -Name $BlueGreenData.VirtualServer.name -Application $BlueGreenData.Application -Partition $BlueGreenData.Partition

                Write-Host $BlueGreenData.VirtualServer.fullPath
                # Output looks backwards, but accurately reflects the change; conditional is used to force output in order by category Blue, then Green
                if ($BlueGreenData.LivePool.Category -eq 'Blue') {
                    Write-Host ("    {0,-5} idle: {1}" -f $BlueGreenData.LivePool.category,$BlueGreenData.LivePool.fullPath)
                    Write-Host ("==> {0,-5} LIVE: {1}" -f $BlueGreenData.IdlePool.category,$BlueGreenData.IdlePool.fullPath)
                    $swapcount++
                } else {
                    Write-Host ("==> {0,-5} LIVE: {1}" -f $BlueGreenData.IdlePool.category,$BlueGreenData.IdlePool.fullPath)
                    Write-Host ("    {0,-5} idle: {1}" -f $BlueGreenData.LivePool.category,$BlueGreenData.LivePool.fullPath)
                    $swapcount++
                }
                if ($BlueGreenData.DeviceGroup) {
                    if (Sync-DeviceToGroup -F5Session $session -GroupName $BlueGreenData.DeviceGroup) {
                        Write-Host ("Synced device to group '{0}'" -f $BlueGreenData.DeviceGroup)
                    } else {
                        Write-Host ("##vso[task.logissue type=warning;] Failed to sync device to group {0}" -f $BlueGreenData.DeviceGroup)
                    }
                }
                Remove-Item -Path $_.FullName -Force
            } catch {
                Write-Host ("##vso[task.logissue type=error;] Failed to swap the active pool for '{0}'; {1}" -f $BlueGreenData.VirtualServer.name,$_.Exception.Message)
                throw New-Object -TypeName System.Exception -ArgumentList ("Failed to swap the active pool for '{0}'; {1}" -f $BlueGreenData.VirtualServer.name,$_.Exception.Message)
            }
        }
        if ($swapcount -eq 0) {
            Write-Host "##vso[task.logissue type=error;] Blue-Green Deployment - Selection data detected, but no swap occured."
            throw New-Object -TypeName System.Exception -ArgumentList "Blue-Green Deployment - Selection data detected, but no swap occured."
        }
    } else {
        Write-Host "##vso[task.logissue type=error;] No Blue-Green Deployment - Selection data found. No swap occured."
        throw New-Object -TypeName System.Exception -ArgumentList "No Blue-Green Deployment - Selection data found. No swap occured."
    }
}