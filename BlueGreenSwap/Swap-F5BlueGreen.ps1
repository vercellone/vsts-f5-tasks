<#
.SYNOPSIS
    Swaps the active pool of a virtual server based on output from a corresponding Select-F5BlueGreen task.
#>
[cmdletBinding()]
param()
process {
    $storagekey = 'F5BlueGreen-{0}-{1}' -f $env:Release_ReleaseId,$env:Release_EnvironmentId
    # Base64-encodes the Personal Access Token (PAT)
    $VstsAccessToken = (Get-EndPoint -Name SystemVssConnection -Require).auth.parameters.AccessToken
    $Auth = @{ Authorization = 'Basic {0}' -f $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$($VstsAccessToken)"))) }
    $uri = '{0}/_apis/ExtensionManagement/InstalledExtensions/vercellj/f5-tasks/Data/Scopes/User/Me/Collections/%24settings/Documents?api-version=3.1-preview.1' -f ($Env:SYSTEM_TEAMFOUNDATIONSERVERURI -replace '\.vsrm\.','.extmgmt.')
    # Store Credentials in JSON as plain text for now.
    $f5Selections = Invoke-RestMethodOverride -Uri $uri -Method Get -Headers $Auth | Select-Object -ExpandProperty Value | Where-Object { $_.id -match "^$storagekey" }
    if ($f5Selections) {
        $swapcount = 0
        $f5Selections | ForEach-Object {
            try {
                $BlueGreenData = Invoke-NullCoalescing {$_.value} {$_}
                # Re-constitute credentials from plaintext
                $SecurePassword = ConvertTo-SecureString $BlueGreenData.Credentials.Password -AsPlainText -Force
                $BlueGreenData.Credentials = [System.Management.Automation.PSCredential]::new($BlueGreenData.Credentials.UserName, $SecurePassword)
                $session = New-F5Session -LTMName $BlueGreenData.LTMName -LTMCredentials $BlueGreenData.Credentials -PassThrough

                $BlueGreenData.VirtualServer.pool = $BlueGreenData.IdlePool.name

                $UpdatedServer = Set-VirtualServer -F5Session $session -Name $BlueGreenData.VirtualServer.name -Application $BlueGreenData.Application -Partition $BlueGreenData.Partition -DefaultPool $BlueGreenData.IdlePool.name -PassThru

                # Validate swap
                if ($UpdatedServer.pool -ne $BlueGreenData.IdlePool.fullPath) {
                    Write-Host "##vso[task.logissue type=error;] Blue-Green Deployment - Swap failed."
                    throw [System.Exception]::new("Blue-Green Deployment - Swap failed.")
                }

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
                $uri = '{0}/_apis/ExtensionManagement/InstalledExtensions/vercellj/f5-tasks/Data/Scopes/User/Me/Collections/%24settings/Documents/{1}?api-version=3.1-preview.1' -f ($Env:SYSTEM_TEAMFOUNDATIONSERVERURI -replace '\.vsrm\.','.extmgmt.'),$_.id
                Invoke-RestMethodOverride -Uri $uri -Method Delete -Headers $Auth
            } catch {
                Write-Host ("##vso[task.logissue type=error;] Failed to swap the active pool for '{0}'; {1}" -f $BlueGreenData.VirtualServer.name,$_.Exception.Message)
                throw [System.Exception]::new("Failed to swap the active pool for '{0}'; {1}" -f $BlueGreenData.VirtualServer.name,$_.Exception.Message)
            }
        }
        if ($swapcount -eq 0) {
            Write-Host "##vso[task.logissue type=error;] Blue-Green Deployment - Selection data detected, but no swap occured."
            throw [System.Exception]::new("Blue-Green Deployment - Selection data detected, but no swap occured.")
        }
    } else {
        Write-Host "##vso[task.logissue type=error;] No Blue-Green Deployment - Selection data found. No swap occured."
        throw [System.Exception]::new("No Blue-Green Deployment - Selection data found. No swap occured.")
    }
}
