<#
.SYNOPSIS
    Selects and categorizes F5 elements as either Blue or Green, validates pool members are mutually exclusive, and persists variable(s) for use by subsequent tasks.
#>
[cmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$LTMName,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$UserName,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Password,

    [Alias('iApp')]
    [Parameter()]
    [string]$Application='',
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Partition,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$VirtualServer,
    [string]$DeviceGroup,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BluePool,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$GreenPool,

    [Parameter()]
    [string]$F5VariablePrefix='F5',
    [Parameter()]
    [string]$MachineListFormat='{1}:5985',
    [Parameter()]
    [string]$ServerListFormat='{1}'
)
begin {
    $Force = $false
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $F5Credentials = [System.Management.Automation.PSCredential]::new($UserName, $SecurePassword)
    $session = New-F5Session -LTMName $LTMName -LTMCredentials $F5Credentials -PassThrough
}
process {
    #region F5 Validation

    #region Virtual Server
    $F5VirtualServer = Get-VirtualServer -F5Session $session -Application $Application -Name $VirtualServer -Partition $Partition -ErrorAction SilentlyContinue
    if ($null -eq $F5VirtualServer) {
        Write-Host "##vso[task.logissue type=error;] '$VirtualServer' virtual server not found."
        throw [System.ArgumentException]::new("'$VirtualServer' virtual server not found.",'VirtualServer')
    }
    Write-Host $F5VirtualServer.fullPath

    #endregion

    #region Pools
    $F5BluePool = Get-Pool -F5Session $session -PoolName $BluePool -Application $Application -Partition $Partition -ErrorAction SilentlyContinue |
        Add-Member -MemberType NoteProperty -Name Category -Value 'Blue' -PassThru |
        Add-Member -MemberType ScriptProperty -Name IsActive -Value { $this.fullPath -eq $($F5VirtualServer.pool) } -PassThru
    if ($null -eq $F5BluePool) {
        Write-Host "##vso[task.logissue type=error;] '$BluePool' BLUE pool not found"
        throw [System.ArgumentException]::new("'$BluePool' BLUE pool not found.",'BluePool')
    }
    $F5GreenPool = Get-Pool -F5Session $session -PoolName $GreenPool -Application $Application -Partition $Partition -ErrorAction SilentlyContinue |
        Add-Member -MemberType NoteProperty -Name Category -Value 'Green' -PassThru |
        Add-Member -MemberType ScriptProperty -Name IsActive -Value { $this.fullPath -eq $($F5VirtualServer.pool) } -PassThru
    if ($null -eq $F5GreenPool) {
        Write-Host "##vso[task.logissue type=error;] '$GreenPool' GREEN pool not found"
        throw [System.ArgumentException]::new("'$GreenPool' GREEN pool not found.",'GreenPool')
    }

    #endregion

    #region BLUE Pool Members
    Write-Host ($(if ($F5BluePool.IsActive) { '==> {0,-5} LIVE: {1}' } else { '    {0,-5} idle: {1}' }) -f $F5BluePool.Category,$F5BluePool.fullPath)
    $F5BlueMembers = $F5BluePool | Get-PoolMember -F5Session $session -ErrorAction SilentlyContinue
    $F5BlueMembers | ForEach-Object {
        Write-Host ('              : {0} ({1}) {2}' -f $_.name,$_.address,$_.Session)
    }
    if ($null -eq $F5BlueMembers) {
        Write-Host "##vso[task.logissue type=error;] '$BluePool' BLUE pool contains no members."
        throw [System.ArgumentException]::new("'$BluePool' BLUE pool contains no members.",'BluePool')
    }
    # test for active pool members
    if (($F5BlueMembers | Where-Object { ( $_.State -eq 'up' -and $_.Session -eq 'monitor-enabled' ) -or ( $_.State -eq 'unchecked' -and $_.Session -eq 'user-enabled' ) }).Count -eq 0) {
        Write-Host "##vso[task.logissue type=warning;] '$BluePool' BLUE pool contains no ACTIVE members.  This is normal only if your application is down due to health monitor(s), as may be the case if your application has not previously been deployed to this pool."
    }
    # test for enabled pool members
    if (($F5BlueMembers | Where-Object { 'monitor-enabled','user-enabled' -contains $_.Session }).Count -eq 0) {
        Write-Host "##vso[task.logissue type=error;] '$BluePool' BLUE pool contains no ENABLED members."
        throw [System.ArgumentException]::new("'$BluePool' BLUE pool contains no ENABLED members.",'BluePool')
    }
    #endregion

    #region GREEN Pool Members
    Write-Host ($(if ($F5GreenPool.IsActive) { '==> {0,-5} LIVE: {1}' } else { '    {0,-5} idle: {1}' }) -f $F5GreenPool.Category,$F5GreenPool.fullPath)
    $F5GreenMembers = $F5GreenPool | Get-PoolMember -F5Session $session -ErrorAction SilentlyContinue
    $F5GreenMembers | ForEach-Object {
        Write-Host ('              : {0} ({1}) {2}' -f $_.name,$_.address,$_.Session)
    }
    if ($null -eq $F5GreenMembers) {
        Write-Host "##vso[task.logissue type=error;] '$GreenPool' GREEN pool contains no members."
        throw [System.ArgumentException]::new("'$GreenPool' ENABLED pool contains no members.",'GreenPool')
    }
    # test for active pool members
    if (($F5GreenMembers | Where-Object { ( $_.State -eq 'up' -and $_.Session -eq 'monitor-enabled' ) -or ( $_.State -eq 'unchecked' -and $_.Session -eq 'user-enabled' ) }).Count -eq 0) {
        Write-Host "##vso[task.logissue type=warning;] '$GreenPool' GREEN pool contains no ACTIVE members.  This is normal only if your application is down due to health monitor(s), as may be the case if your application has not previously been deployed to this pool."
    }
    # test for enabled pool members
    if (($F5GreenMembers | Where-Object { 'monitor-enabled','user-enabled' -contains $_.Session }).Count -eq 0) {
        Write-Host "##vso[task.logissue type=error;] '$GreenPool' GREEN pool contains no ENABLED members."
        throw [System.ArgumentException]::new("'$GreenPool' GREEN pool contains no ENABLED members.",'GreenPool')
    }
    #endregion

    #region Other F5 validation

    $collisions = Compare-Object -ReferenceObject $F5BlueMembers.GetFullName() -DifferenceObject $F5GreenMembers.GetFullName() -IncludeEqual | Where-Object SideIndicator -eq '=='
    if (![bool]$Force -and ($null -ne $collisions)) {
        $collisions | ForEach-Object {
            Write-Host ("##vso[task.logissue type=warning;] Pool member collision: {0}" -f $_.InputObject)
        }
        Write-Host "##vso[task.logissue type=error;] Pool member collision(s) detected.  Pool members cannot exist in both the Blue and Green pools"
        throw [System.ArgumentException]::new("'$GreenPool' Pool member collision(s) detected.  Pool members cannot exist in both Blue and Green",'GreenPool')
    }

    #endregion

    #endregion

    # Set variables for subsequent tasks to target the idle servers
    $MachineList = @()
    $ServerList = @()
    if (!$F5BluePool.IsActive) {
        $F5BlueMembers | ForEach-Object {
            $name,$port = $_.name -split ':'
            $MachineList += $MachineListFormat -f $_.address,$name,$port
            $ServerList += $ServerListFormat -f $_.address,$name,$port
        }
    } else {
        $F5GreenMembers | ForEach-Object {
            $name,$port = $_.name -split ':'
            $MachineList += $MachineListFormat -f $_.address,$name,$port
            $ServerList += $ServerListFormat -f $_.address,$name,$port
        }
    }
    Write-Host ("##vso[task.setvariable variable={0}MachineList]{1}"  -f $F5VariablePrefix,($MachineList -join ','))
    Write-Host ("##vso[task.setvariable variable={0}ServerList]{1}" -f $F5VariablePrefix,($ServerList -join ','))

    $f5Selections = [pscustomobject]@{
        LTMName = $LTMName
        Credentials = $F5Credentials
        Application = $Application
        Partition = $Partition
        VirtualServer = $F5VirtualServer
        DeviceGroup = $DeviceGroup
        Force = [bool]$Force
        IdlePool = if (!$F5BluePool.IsActive) { $F5BluePool } else { $F5GreenPool }
        LivePool = if ($F5BluePool.IsActive) { $F5BluePool } else { $F5GreenPool }
    }
    $storagekey = 'F5BlueGreen-{0}-{1}-{2}' -f $env:Release_ReleaseId,$env:Release_EnvironmentId,$VirtualServer
    # Base64-encodes the Personal Access Token (PAT)
    $VstsAccessToken = (Get-EndPoint -Name SystemVssConnection -Require).auth.parameters.AccessToken
    $Auth = @{ Authorization = 'Basic {0}' -f $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$($VstsAccessToken)"))) }
    $uri = '{0}/_apis/ExtensionManagement/InstalledExtensions/vercellj/f5-tasks/Data/Scopes/User/Me/Collections/%24settings/Documents?api-version=3.1-preview.1' -f ($Env:SYSTEM_TEAMFOUNDATIONSERVERURI -replace '\.vsrm\.','.extmgmt.')

    # Store Credentials in JSON as plain text for now.
    $f5Selections.Credentials = [pscustomobject]@{username=$F5Credentials.UserName;password=$F5Credentials.GetNetworkCredential().Password}
    $body = [pscustomobject]@{
        id = $storagekey
        '__etag' = -1
        'value' = $f5Selections
    } | ConvertTo-Json
    Invoke-RestMethodOverride -Uri $uri -Method Put -Headers $Auth -ContentType 'application/json' -Body $body | Out-Null
}