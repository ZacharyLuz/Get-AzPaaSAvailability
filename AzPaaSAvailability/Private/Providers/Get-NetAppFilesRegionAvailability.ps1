function Get-NetAppFilesRegionAvailability {
    <#
    .SYNOPSIS
        Queries Azure NetApp Files region information, quota limits, and usage.
    .DESCRIPTION
        Calls Microsoft.NetApp location APIs to discover regional support, logical
        availability zone mappings, storage-to-network proximity, and quota headroom.
    #>
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$AccessToken,
        [string]$ArmUrl = 'https://management.azure.com',
        [string]$ApiVersion = '2026-01-01',
        [int]$MaxRetries = 3
    )

    $locationBaseUri = "$ArmUrl/subscriptions/$SubscriptionId/providers/Microsoft.NetApp/locations/$Region"
    $headers = @{ Authorization = "Bearer $AccessToken" }

    try {
        $regionInfoUri = "$locationBaseUri/regionInfos/default?api-version=$ApiVersion"
        $regionInfo = Invoke-WithRetry -MaxRetries $MaxRetries -OperationName "NetApp Files RegionInfo ($Region)" -ScriptBlock {
            Invoke-RestMethod -Uri $regionInfoUri -Headers $headers -Method GET -TimeoutSec 30
        }
    }
    catch {
        Write-Verbose "NetApp Files region info unavailable for $Region`: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Region                    = $Region
            Service                   = 'NetAppFiles'
            Status                    = 'Unavailable'
            AvailabilityZones         = ''
            ZoneCount                 = 0
            StorageToNetworkProximity = $null
            QuotaLimits               = @()
            Usages                    = @()
            TotalTiBsLimit            = $null
            TotalTiBsUsed             = $null
            TotalTiBsAvailable        = $null
            ActionRequired            = 'Region info unavailable'
        }
    }

    $quotaError = $null
    $usageError = $null
    $quotaResponse = $null
    $usageResponse = $null

    try {
        $quotaUri = "$locationBaseUri/quotaLimits?api-version=$ApiVersion"
        $quotaResponse = Invoke-WithRetry -MaxRetries $MaxRetries -OperationName "NetApp Files QuotaLimits ($Region)" -ScriptBlock {
            Invoke-RestMethod -Uri $quotaUri -Headers $headers -Method GET -TimeoutSec 30
        }
    }
    catch {
        $quotaError = $_.Exception.Message
        Write-Verbose "NetApp Files quota limits unavailable for $Region`: $quotaError"
    }

    try {
        $usageUri = "$locationBaseUri/usages?api-version=$ApiVersion"
        $usageResponse = Invoke-WithRetry -MaxRetries $MaxRetries -OperationName "NetApp Files Usages ($Region)" -ScriptBlock {
            Invoke-RestMethod -Uri $usageUri -Headers $headers -Method GET -TimeoutSec 30
        }
    }
    catch {
        $usageError = $_.Exception.Message
        Write-Verbose "NetApp Files usages unavailable for $Region`: $usageError"
    }

    $availabilityZoneMappings = @($regionInfo.properties.availabilityZoneMappings)
    $availableZones = @($availabilityZoneMappings | Where-Object { $_.isAvailable } | ForEach-Object { $_.availabilityZone })

    $quotaLimits = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($quotaLimit in @($quotaResponse.value)) {
        $quotaName = ($quotaLimit.name -split '/')[-1]
        $quotaLimits.Add([PSCustomObject]@{
            Name        = $quotaName
            DisplayName = $quotaName
            Default     = $quotaLimit.properties.default
            Current     = $quotaLimit.properties.current
            Usage       = $quotaLimit.properties.usage
        })
    }

    $usages = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($usageResult in @($usageResponse.value)) {
        $usages.Add([PSCustomObject]@{
            Name         = $usageResult.name.value
            DisplayName  = $usageResult.name.localizedValue
            CurrentValue = $usageResult.properties.currentValue
            Limit        = $usageResult.properties.limit
            Unit         = $usageResult.properties.unit
        })
    }

    $totalTiBsUsage = @($usages | Where-Object { $_.Name -and $_.Name.ToLowerInvariant() -eq 'totaltibspersubscription' } | Select-Object -First 1)
    $totalTiBsQuota = @($quotaLimits | Where-Object { $_.Name -and $_.Name.ToLowerInvariant() -eq 'totaltibspersubscription' } | Select-Object -First 1)

    $totalTiBsUsed = if ($totalTiBsUsage.Count -gt 0) { $totalTiBsUsage[0].CurrentValue } else { $null }
    $totalTiBsLimit = if ($totalTiBsUsage.Count -gt 0) { $totalTiBsUsage[0].Limit } elseif ($totalTiBsQuota.Count -gt 0) { $totalTiBsQuota[0].Current } else { $null }
    $totalTiBsAvailable = if ($null -ne $totalTiBsUsed -and $null -ne $totalTiBsLimit) { [math]::Max(0, $totalTiBsLimit - $totalTiBsUsed) } else { $null }

    $status = if ($quotaError -or $usageError) { 'Unknown' } else { 'Available' }
    $actionRequired = 'None'
    if ($quotaError -or $usageError) {
        $actionRequired = 'Quota or usage lookup incomplete'
    }
    elseif ($null -ne $totalTiBsUsed -and $null -ne $totalTiBsLimit -and $totalTiBsUsed -ge $totalTiBsLimit) {
        $actionRequired = 'Quota exhausted - request increase'
    }

    return [PSCustomObject]@{
        Region                    = $Region
        Service                   = 'NetAppFiles'
        Status                    = $status
        AvailabilityZones         = ($availableZones -join ',')
        ZoneCount                 = $availableZones.Count
        StorageToNetworkProximity = $regionInfo.properties.storageToNetworkProximity
        QuotaLimits               = $quotaLimits.ToArray()
        Usages                    = $usages.ToArray()
        TotalTiBsLimit            = $totalTiBsLimit
        TotalTiBsUsed             = $totalTiBsUsed
        TotalTiBsAvailable        = $totalTiBsAvailable
        ActionRequired            = $actionRequired
    }
}