function Export-AzPaaSAvailabilityReport {
    <#
    .SYNOPSIS
        Exports PaaS availability scan results to CSV or XLSX.
    .DESCRIPTION
        Takes the output from Get-AzPaaSAvailability and exports to file.
        Supports CSV and XLSX (via ImportExcel module) formats.
    .PARAMETER ScanResult
        Output object from Get-AzPaaSAvailability.
    .PARAMETER Path
        Export directory path.
    .PARAMETER Format
        Auto (detect XLSX capability), CSV, or XLSX.
    .EXAMPLE
        $r = Get-AzPaaSAvailability -Region eastus -Quiet
        Export-AzPaaSAvailabilityReport -ScanResult $r -Path C:\Temp
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '', Justification = 'Exporter handles a single scan result object and preserves existing direct-call behavior.')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][PSCustomObject]$ScanResult,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Auto', 'CSV', 'XLSX')][string]$Format = 'Auto'
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    # Detect XLSX capability
    $canXlsx = $false
    if ($Format -in @('XLSX', 'Auto')) {
        $mod = Get-Module ImportExcel -ListAvailable -ErrorAction SilentlyContinue
        if ($mod) {
            Import-Module ImportExcel -ErrorAction Stop -WarningAction SilentlyContinue
            $canXlsx = $true
        }
    }
    $useXlsx = ($Format -eq 'XLSX') -or ($Format -eq 'Auto' -and $canXlsx)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    # Build SQL export rows
    $sqlRows = @()
    if ($ScanResult.SqlSkus -and $ScanResult.SqlSkus.Count -gt 0) {
        foreach ($sku in $ScanResult.SqlSkus) {
            $sqlRows += [PSCustomObject]@{
                Region            = $sku.Region
                ResourceType      = $sku.ResourceType
                Edition           = $sku.Edition
                SKU               = $sku.SKU
                Family            = $sku.Family
                vCores            = $sku.vCores
                ComputeModel      = $sku.ComputeModel
                ZoneRedundant     = $sku.ZoneRedundant
                AHUBSupported     = $sku.AHUBSupported
                StorageRedundancy = $sku.StorageRedundancy
                Status            = $sku.Status
                ServerQuota_Used  = $sku.ServerQuotaUsed
                ServerQuota_Limit = $sku.ServerQuotaLimit
                VCoreQuota_Used   = $sku.VCoreQuotaUsed
                VCoreQuota_Limit  = $sku.VCoreQuotaLimit
            }
        }
    }

    # Build Cosmos DB export rows
    $cosmosRows = @()
    if ($ScanResult.CosmosDbLocations -and $ScanResult.CosmosDbLocations.Count -gt 0) {
        foreach ($loc in $ScanResult.CosmosDbLocations) {
            $cosmosRows += [PSCustomObject]@{
                Region                    = $loc.Region
                DisplayName               = $loc.DisplayName
                SupportsAZ                = $loc.SupportsAZ
                SubscriptionAccessAZ      = $loc.AccessAllowedAZ
                SubscriptionAccessRegular = $loc.AccessAllowedRegular
                IsResidencyRestricted     = $loc.IsResidencyRestricted
                BackupRedundancies        = $loc.BackupRedundancies
                Status                    = $loc.Status
                ActionRequired            = $loc.ActionRequired
            }
        }
    }

    # Build Azure NetApp Files export rows
    $netAppRows = @()
    if ($ScanResult.NetAppFiles -and $ScanResult.NetAppFiles.Count -gt 0) {
        foreach ($netAppRegion in $ScanResult.NetAppFiles) {
            $quotaSummary = @($netAppRegion.QuotaLimits | ForEach-Object { "$($_.Name): default=$($_.Default), current=$($_.Current), usage=$($_.Usage)" }) -join '; '
            $usageSummary = @($netAppRegion.Usages | ForEach-Object { "$($_.Name): $($_.CurrentValue)/$($_.Limit) $($_.Unit)" }) -join '; '

            $netAppRows += [PSCustomObject]@{
                Region                    = $netAppRegion.Region
                Status                    = $netAppRegion.Status
                AvailabilityZones         = $netAppRegion.AvailabilityZones
                ZoneCount                 = $netAppRegion.ZoneCount
                StorageToNetworkProximity = $netAppRegion.StorageToNetworkProximity
                TotalTiBsUsed             = $netAppRegion.TotalTiBsUsed
                TotalTiBsLimit            = $netAppRegion.TotalTiBsLimit
                TotalTiBsAvailable        = $netAppRegion.TotalTiBsAvailable
                ActionRequired            = $netAppRegion.ActionRequired
                QuotaLimits               = $quotaSummary
                Usages                    = $usageSummary
            }
        }
    }

    if ($useXlsx) {
        $xlsxFile = Join-Path $Path "AzPaaSAvailability-$timestamp.xlsx"
        $createdWorkbook = $false
        if ($sqlRows.Count -gt 0) {
            $sqlRows | Export-Excel -Path $xlsxFile -WorksheetName 'SQL SKUs' -AutoSize -FreezeTopRow -AutoFilter
            $createdWorkbook = $true
        }
        if ($cosmosRows.Count -gt 0) {
            $cosmosExportParams = @{ Path = $xlsxFile; WorksheetName = 'Cosmos DB Access'; AutoSize = $true; FreezeTopRow = $true; AutoFilter = $true }
            if ($createdWorkbook) { $cosmosExportParams.Append = $true }
            $cosmosRows | Export-Excel @cosmosExportParams
            $createdWorkbook = $true
        }
        if ($netAppRows.Count -gt 0) {
            $netAppExportParams = @{ Path = $xlsxFile; WorksheetName = 'NetApp Files'; AutoSize = $true; FreezeTopRow = $true; AutoFilter = $true }
            if ($createdWorkbook) { $netAppExportParams.Append = $true }
            $netAppRows | Export-Excel @netAppExportParams
            $createdWorkbook = $true
        }
        Write-Host "Exported: $xlsxFile (SQL: $($sqlRows.Count) rows, Cosmos: $($cosmosRows.Count) rows, NetApp Files: $($netAppRows.Count) rows)" -ForegroundColor Green
    }
    else {
        if ($sqlRows.Count -gt 0) {
            $f = Join-Path $Path "AzPaaSAvailability-SQL-$timestamp.csv"
            $sqlRows | Export-Csv -Path $f -NoTypeInformation
            Write-Host "SQL: $f ($($sqlRows.Count) rows)" -ForegroundColor Green
        }
        if ($cosmosRows.Count -gt 0) {
            $f = Join-Path $Path "AzPaaSAvailability-CosmosDB-$timestamp.csv"
            $cosmosRows | Export-Csv -Path $f -NoTypeInformation
            Write-Host "Cosmos DB: $f ($($cosmosRows.Count) rows)" -ForegroundColor Green
        }
        if ($netAppRows.Count -gt 0) {
            $f = Join-Path $Path "AzPaaSAvailability-NetAppFiles-$timestamp.csv"
            $netAppRows | Export-Csv -Path $f -NoTypeInformation
            Write-Host "Azure NetApp Files: $f ($($netAppRows.Count) rows)" -ForegroundColor Green
        }
    }
}
