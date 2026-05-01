# Usage Examples

Common scan patterns for `Get-AzPaaSAvailability`.

Region values use ARM region codes such as `southcentralus`; shorthand names like `southcentral` are not valid Azure locations.

## Azure NetApp Files

Check regional ANF access, logical zones, storage-to-network proximity, and quota headroom:

```powershell
Import-Module ./AzPaaSAvailability

Get-AzNetAppFilesAvailability -Region eastus,westus2
```

Use the orchestrator when you want NetApp Files included in the same output contract and export flow as the rest of the PaaS scanner:

```powershell
$results = Get-AzPaaSAvailability -Service NetAppFiles -Region eastus,westus2 -Quiet

$results.NetAppFiles |
    Select-Object Region, Status, AvailabilityZones, StorageToNetworkProximity, TotalTiBsAvailable, ActionRequired
```

Export NetApp Files results to CSV or XLSX:

```powershell
$results = Get-AzPaaSAvailability -Service NetAppFiles -Region eastus,westus2 -Quiet
$results | Export-AzPaaSAvailabilityReport -Path C:\Temp\AzPaaSAvailability -Format XLSX
```

Run the backward-compatible wrapper without importing the module first:

```powershell
.\Get-AzPaaSAvailability.ps1 -Service NetAppFiles -Region eastus,westus2 -NoPrompt
```

## Region Matrix

Compare all dedicated PaaS service signals across major US regions:

```powershell
Get-AzPaaSAvailability -RegionPreset USMajor
```

The matrix includes an `ANF` column. Available NetApp Files regions show `AZ{count}` when logical zones are returned.

## SQL Database

Scan only SQL Database Hyperscale availability:

```powershell
Get-AzPaaSAvailability -Service SqlDatabase -Edition Hyperscale -Region eastus,westus2
```

Return objects only for automation:

```powershell
$results = Get-AzPaaSAvailability -Service SqlDatabase -Region eastus -Quiet
$results.SqlSkus | Where-Object { $_.ZoneRedundant }
```

## Cosmos DB Region Access

Check whether a subscription can deploy Cosmos DB in selected regions:

```powershell
Get-AzCosmosDBAvailability -Region eastus,westeurope
```

## Static-Tier Services

Validate pricing-backed static tiers for selected services:

```powershell
Get-AzServiceTierAvailability -Region eastus -ServiceFilter Redis,EventHubs,ServiceBus
```

## Sovereign Clouds

Use a region preset when the environment can be inferred:

```powershell
.\Get-AzPaaSAvailability.ps1 -RegionPreset USGov -NoPrompt
```

Or pass the cloud explicitly:

```powershell
Get-AzPaaSAvailability -Region usgovvirginia -Environment AzureUSGovernment
```

## JSON Output

Use the wrapper for JSON output suitable for automation:

```powershell
.\Get-AzPaaSAvailability.ps1 -Service NetAppFiles -Region eastus -NoPrompt -JsonOutput
```