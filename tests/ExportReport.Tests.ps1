#Requires -Modules Pester

BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..' 'AzPaaSAvailability'
    . (Join-Path $moduleRoot 'Public' 'Export-AzPaaSAvailabilityReport.ps1')
}

Describe 'Export-AzPaaSAvailabilityReport' {
    It 'does not report a successful XLSX export when there are no rows' {
        $scanResult = [PSCustomObject]@{
            SqlSkus           = @()
            CosmosDbLocations = @()
            NetAppFiles       = @()
        }

        Export-AzPaaSAvailabilityReport -ScanResult $scanResult -Path $TestDrive -Format XLSX -WarningVariable warnings 3>$null

        @($warnings | ForEach-Object { $_.ToString() }) | Should -Contain 'No exportable rows found; no XLSX file was created.'
        Get-ChildItem -Path $TestDrive -Filter '*.xlsx' | Should -HaveCount 0
    }
}