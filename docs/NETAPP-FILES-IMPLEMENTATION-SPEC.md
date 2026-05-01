# Azure NetApp Files Implementation Spec

## Goal

Add Azure NetApp Files regional availability to `Get-AzPaaSAvailability` as a first-class service named `NetAppFiles`.

The feature should answer deployment-planning questions that Azure Storage account SKU scans cannot answer:

- Is Azure NetApp Files supported in this region for this subscription?
- Which logical availability zones are usable for ANF in this region?
- What storage-to-network proximity is exposed for placement planning?
- What regional NetApp quota limits and current usage could block deployment?

## Non-Goals

- Do not create, modify, or delete NetApp accounts, pools, or volumes.
- Do not perform quota availability POST checks in the first implementation.
- Do not claim pricing parity until Azure Retail Prices API service and meter filters are verified.
- Do not enumerate existing customer NetApp accounts or volumes.

## API Version

Use the latest stable NetApp resource provider API found in Azure REST API specs:

```text
2026-01-01
```

Verified stable paths and example payloads:

- `GET /subscriptions/{subscriptionId}/providers/Microsoft.NetApp/locations/{location}/regionInfos/default?api-version=2026-01-01`
- `GET /subscriptions/{subscriptionId}/providers/Microsoft.NetApp/locations/{location}/quotaLimits?api-version=2026-01-01`
- `GET /subscriptions/{subscriptionId}/providers/Microsoft.NetApp/locations/{location}/usages?api-version=2026-01-01`

The 2026-01-01 swagger keeps the same core region/quota/usage shapes as 2025-12-01 and includes the current `ServiceLevel` enum: `Standard`, `Premium`, `Ultra`, `StandardZRS`, and `Flexible`. `StandardZRS` is marked as deprecated soon in the swagger; `Elastic` appears in Microsoft Learn service-level guidance but is not in the 2026-01-01 `ServiceLevel` enum.

## Output Contract

Each scanned region returns one object:

| Property | Type | Source | Purpose |
|----------|------|--------|---------|
| `Region` | string | input | Region code |
| `Service` | string | static | `NetAppFiles` |
| `Status` | string | derived | `Available`, `Unavailable`, or `Unknown` |
| `AvailabilityZones` | string | `availabilityZoneMappings` | Comma-separated available logical zones |
| `ZoneCount` | int | derived | Number of available logical zones |
| `StorageToNetworkProximity` | string | `storageToNetworkProximity` | Placement/proximity signal |
| `QuotaLimits` | object[] | `quotaLimits.value` | Normalized quota limit rows |
| `Usages` | object[] | `usages.value` | Normalized current usage rows |
| `TotalTiBsLimit` | int/null | usages or quota | Regional TiB limit when available |
| `TotalTiBsUsed` | int/null | usages | Regional TiB usage when available |
| `TotalTiBsAvailable` | int/null | derived | Remaining TiB headroom when available |
| `ActionRequired` | string | derived | Human-readable deployment blocker/action |

Quota limit rows:

| Property | Type |
|----------|------|
| `Name` | string |
| `DisplayName` | string |
| `Default` | int/null |
| `Current` | int/null |
| `Usage` | int/null |

Usage rows:

| Property | Type |
|----------|------|
| `Name` | string |
| `DisplayName` | string |
| `CurrentValue` | int/null |
| `Limit` | int/null |
| `Unit` | string |

## Derived Status Rules

- `Available`: region info call succeeds.
- `Unavailable`: region info call fails with a not-found, bad-request, or provider availability error for that region.
- `Unknown`: region info succeeds but quota or usage calls fail; keep partial region data and put the failure in `ActionRequired`.
- `ActionRequired = None`: region info and quota/usage calls all succeed and no known limit is exhausted.
- `ActionRequired = Quota exhausted - request increase`: total TiB usage is at or above limit.

## Module Integration

Add:

- `AzPaaSAvailability/Private/Providers/Get-NetAppFilesRegionAvailability.ps1`
- `AzPaaSAvailability/Public/Get-AzNetAppFilesAvailability.ps1`

Update:

- `AzPaaSAvailability/Public/Get-AzPaaSAvailability.ps1`
  - Add `NetAppFiles` to `-Service`.
  - Add a scan flag, banner label, invocation, result property, matrix data, stats, and metadata service entry.
- `AzPaaSAvailability/Public/Show-AzPaaSRegionMatrix.ps1`
  - Add an `ANF` column with zone count when available.
- `AzPaaSAvailability/Public/Export-AzPaaSAvailabilityReport.ps1`
  - Add CSV/XLSX export rows for NetApp Files.
- `AzPaaSAvailability/AzPaaSAvailability.psd1`
  - Export `Get-AzNetAppFilesAvailability`.
- `README.md`, `CHANGELOG.md`, and `docs/PAAS-SERVICE-INVENTORY.md`.

## Display Behavior

`Get-AzNetAppFilesAvailability` should mirror the other scanner cmdlets:

```powershell
Get-AzNetAppFilesAvailability -Region eastus,westus2
Get-AzPaaSAvailability -Service NetAppFiles -Region eastus
```

Console output per region should summarize:

- available logical zone count,
- storage-to-network proximity,
- total TiB usage/limit when present,
- action required.

## Testing Plan

Add focused Pester tests for the private provider parser:

- Parses region info zone mappings and proximity.
- Normalizes quota limits.
- Normalizes usages.
- Derives total TiB headroom.
- Keeps quota limits empty when the quota API fails after region info succeeds.
- Keeps usages empty when the usages API fails after region info succeeds.
- Returns an unavailable object when region info fails.
- Verifies XLSX export does not report success when no workbook is created.

Run:

```powershell
Invoke-Pester ./tests -Output Detailed
```

Run module import/syntax validation through the existing validation script where possible:

```powershell
.\tools\Validate-Script.ps1
```

## Future Work

- Add `checkQuotaAvailability` POST support for planned account/pool/volume names.
- Verify Azure Retail Prices API `serviceName` and meter names before adding `-FetchPricing` support.
- Consider exposing `Flexible` throughput guidance in a dedicated planning view if the broader tool gains service-level filters.