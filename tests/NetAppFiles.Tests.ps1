#Requires -Modules Pester

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..' 'AzPaaSAvailability'
    Get-ChildItem "$moduleRoot\Private" -Recurse -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}

Describe 'Get-NetAppFilesRegionAvailability' {
    BeforeAll {
        function Invoke-WithRetry { param($ScriptBlock, $MaxRetries, $OperationName) $null = $MaxRetries; $null = $OperationName; & $ScriptBlock }
    }

    BeforeEach {
        Mock Invoke-RestMethod {
            if ($Uri -like '*/regionInfos/default*') {
                return [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        storageToNetworkProximity = 'T2'
                        availabilityZoneMappings  = @(
                            [PSCustomObject]@{ availabilityZone = '1'; isAvailable = $true }
                            [PSCustomObject]@{ availabilityZone = '2'; isAvailable = $true }
                            [PSCustomObject]@{ availabilityZone = '3'; isAvailable = $false }
                        )
                    }
                }
            }

            if ($Uri -like '*/quotaLimits*') {
                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            name       = 'eastus/totalTiBsPerSubscription'
                            properties = [PSCustomObject]@{ default = 25; current = 100; usage = 40 }
                        }
                    )
                }
            }

            if ($Uri -like '*/usages*') {
                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            name       = [PSCustomObject]@{ value = 'totalTiBsPerSubscription'; localizedValue = 'Total TiBs per Subscription' }
                            properties = [PSCustomObject]@{ currentValue = 40; limit = 100; unit = 'TiB' }
                        }
                    )
                }
            }
        }
    }

    It 'parses available zones and proximity' {
        $result = Get-NetAppFilesRegionAvailability -Region 'eastus' -SubscriptionId 'sub' -AccessToken 'token'

        $result.Status | Should -Be 'Available'
        $result.AvailabilityZones | Should -Be '1,2'
        $result.ZoneCount | Should -Be 2
        $result.StorageToNetworkProximity | Should -Be 'T2'
    }

    It 'normalizes quota limits' {
        $result = Get-NetAppFilesRegionAvailability -Region 'eastus' -SubscriptionId 'sub' -AccessToken 'token'

        $result.QuotaLimits | Should -HaveCount 1
        $result.QuotaLimits[0].Name | Should -Be 'totalTiBsPerSubscription'
        $result.QuotaLimits[0].Current | Should -Be 100
        $result.QuotaLimits[0].Usage | Should -Be 40
    }

    It 'normalizes usages and calculates TiB headroom' {
        $result = Get-NetAppFilesRegionAvailability -Region 'eastus' -SubscriptionId 'sub' -AccessToken 'token'

        $result.Usages | Should -HaveCount 1
        $result.TotalTiBsUsed | Should -Be 40
        $result.TotalTiBsLimit | Should -Be 100
        $result.TotalTiBsAvailable | Should -Be 60
        $result.ActionRequired | Should -Be 'None'
    }

    It 'keeps quota limits empty when quota lookup fails' {
        Mock Invoke-RestMethod {
            if ($Uri -like '*/regionInfos/default*') {
                return [PSCustomObject]@{ properties = [PSCustomObject]@{ storageToNetworkProximity = 'T2'; availabilityZoneMappings = @() } }
            }

            if ($Uri -like '*/quotaLimits*') { throw 'quota unavailable' }

            return [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name       = [PSCustomObject]@{ value = 'totalTiBsPerSubscription'; localizedValue = 'Total TiBs per Subscription' }
                        properties = [PSCustomObject]@{ currentValue = 40; limit = 100; unit = 'TiB' }
                    }
                )
            }
        }

        $result = Get-NetAppFilesRegionAvailability -Region 'eastus' -SubscriptionId 'sub' -AccessToken 'token'

        $result.Status | Should -Be 'Unknown'
        $result.QuotaLimits | Should -HaveCount 0
        $result.Usages | Should -HaveCount 1
        $result.ActionRequired | Should -Be 'Quota or usage lookup incomplete'
    }

    It 'keeps usages empty when usage lookup fails' {
        Mock Invoke-RestMethod {
            if ($Uri -like '*/regionInfos/default*') {
                return [PSCustomObject]@{ properties = [PSCustomObject]@{ storageToNetworkProximity = 'T2'; availabilityZoneMappings = @() } }
            }

            if ($Uri -like '*/quotaLimits*') {
                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            name       = 'eastus/totalTiBsPerSubscription'
                            properties = [PSCustomObject]@{ default = 25; current = 100; usage = 40 }
                        }
                    )
                }
            }

            throw 'usage unavailable'
        }

        $result = Get-NetAppFilesRegionAvailability -Region 'eastus' -SubscriptionId 'sub' -AccessToken 'token'

        $result.Status | Should -Be 'Unknown'
        $result.QuotaLimits | Should -HaveCount 1
        $result.Usages | Should -HaveCount 0
        $result.ActionRequired | Should -Be 'Quota or usage lookup incomplete'
    }

    It 'marks exhausted regional TiB quota as action required' {
        Mock Invoke-RestMethod {
            if ($Uri -like '*/regionInfos/default*') {
                return [PSCustomObject]@{ properties = [PSCustomObject]@{ storageToNetworkProximity = 'T2'; availabilityZoneMappings = @() } }
            }

            if ($Uri -like '*/quotaLimits*') {
                return [PSCustomObject]@{ value = @() }
            }

            return [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name       = [PSCustomObject]@{ value = 'totalTiBsPerSubscription'; localizedValue = 'Total TiBs per Subscription' }
                        properties = [PSCustomObject]@{ currentValue = 100; limit = 100; unit = 'TiB' }
                    }
                )
            }
        }

        $result = Get-NetAppFilesRegionAvailability -Region 'eastus' -SubscriptionId 'sub' -AccessToken 'token'

        $result.ActionRequired | Should -Be 'Quota exhausted - request increase'
        $result.TotalTiBsAvailable | Should -Be 0
    }

    It 'returns unavailable when region info fails' {
        Mock Invoke-RestMethod {
            if ($Uri -like '*/regionInfos/default*') { throw 'Region not supported' }
            return [PSCustomObject]@{ value = @() }
        }

        $result = Get-NetAppFilesRegionAvailability -Region 'antarctica' -SubscriptionId 'sub' -AccessToken 'token'

        $result.Status | Should -Be 'Unavailable'
        $result.ActionRequired | Should -Be 'Region info unavailable'
        $result.ZoneCount | Should -Be 0
    }
}