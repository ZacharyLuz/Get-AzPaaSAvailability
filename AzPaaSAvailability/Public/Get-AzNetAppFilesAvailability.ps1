function Get-AzNetAppFilesAvailability {
    <#
    .SYNOPSIS
        Scans Azure NetApp Files regional availability, zones, quota, and usage.
    .DESCRIPTION
        Queries Microsoft.NetApp location APIs for each region and returns one
        planning object per region.
    .EXAMPLE
        Get-AzNetAppFilesAvailability -Region eastus,westus2
    .EXAMPLE
        Get-AzNetAppFilesAvailability -Region eastus -Quiet | Select-Object Region, ZoneCount, TotalTiBsAvailable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Region,
        [string]$SubscriptionId,
        [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud', 'AzureGermanCloud')]
        [string]$Environment,
        [int]$MaxRetries = 3,
        [switch]$Quiet
    )

    $endpoints = Resolve-AzureEndpoints -EnvironmentName $Environment
    $icons = Resolve-IconSet
    if (-not $SubscriptionId) { $SubscriptionId = (Get-AzContext -ErrorAction Stop).Subscription.Id }
    $accessToken = Get-AzBearerToken -ResourceUrl $endpoints.ResourceManagerUrl

    if (-not $Quiet) { Write-Host "Scanning Azure NetApp Files in $($Region.Count) region(s)..." -ForegroundColor Yellow }

    $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($regionCode in $Region) {
        try {
            $result = Get-NetAppFilesRegionAvailability -Region $regionCode -SubscriptionId $SubscriptionId `
                -AccessToken $accessToken -ArmUrl $endpoints.ResourceManagerUrl -MaxRetries $MaxRetries
            $allResults.Add($result)

            if (-not $Quiet) {
                $zoneDisplay = if ($result.ZoneCount -gt 0) { "AZ: $($result.AvailabilityZones)" } else { 'AZ: none' }
                $quotaDisplay = if ($null -ne $result.TotalTiBsUsed -and $null -ne $result.TotalTiBsLimit) { "TiB: $($result.TotalTiBsUsed)/$($result.TotalTiBsLimit)" } else { 'TiB: unavailable' }
                $icon = if ($result.Status -eq 'Available') { $icons.Check } elseif ($result.Status -eq 'Unknown') { $icons.Warning } else { $icons.Error }
                $color = if ($result.Status -eq 'Available' -and $result.ActionRequired -eq 'None') { 'Green' } elseif ($result.Status -eq 'Unknown') { 'Yellow' } else { 'Red' }

                Write-Host "  $icon $regionCode`: $($result.Status), $zoneDisplay, proximity: $($result.StorageToNetworkProximity), $quotaDisplay" -ForegroundColor $color
                if ($result.ActionRequired -ne 'None') {
                    Write-Host "     Action: $($result.ActionRequired)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Verbose "NetApp Files scan failed for $regionCode`: $($_.Exception.Message)"
            if (-not $Quiet) { Write-Host "  $($icons.Error) $regionCode`: $($_.Exception.Message)" -ForegroundColor Red }
            $allResults.Add([PSCustomObject]@{
                Region                    = $regionCode
                Service                   = 'NetAppFiles'
                Status                    = 'Unknown'
                AvailabilityZones         = ''
                ZoneCount                 = 0
                StorageToNetworkProximity = $null
                QuotaLimits               = @()
                Usages                    = @()
                TotalTiBsLimit            = $null
                TotalTiBsUsed             = $null
                TotalTiBsAvailable        = $null
                ActionRequired            = 'Scan failed'
            })
        }
    }

    return $allResults
}