# TenantPulse

TenantPulse is an Azure Functions (PowerShell) solution that exports Entra ID and Azure governance/security reports to Azure Blob Storage on scheduled intervals. It is designed for tenant operations teams that need repeatable exports in `json`, `csv`, and `html` formats.

## Highlights

- Scheduled identity and governance exports on Azure Functions timers.
- Centralized report configuration in `function/exports.config.json`.
- Shared module architecture in `function/Modules/Reporting/Reporting.psm1`.
- Multi-format output (`json`, `csv`, `html`) to Azure Blob Storage.
- Managed identity authentication for Microsoft Graph and Azure access.

## Quick Start

1. Connect to Azure with an identity that can deploy resources and assign Graph app roles.
2. Configure `function/exports.config.json` for your tenant/report scope (enabled exports, formats, storage targets, and report-specific settings).
3. Review schedule defaults in `deploy/main.bicep` (`EXPORT_*_SCHEDULE`) and set your own UTC NCRONTAB values before deployment.
4. Run full deployment:
   - `pwsh ./deploy/deploy.ps1 @fullDeployParams`
5. Full deployment behavior (in order):
   - Step 1: `deploy/1-provision-infra.ps1` deploys `deploy/main.bicep`.
   - Step 2: `deploy/2-assign-graph-permissions.ps1` assigns required Graph app permissions to the function managed identity.
   - Step 3: `deploy/3-restore-function-modules.ps1` restores required modules into `function/Modules`.
   - Step 4: `deploy/4-deploy-function-code.ps1` packages `function/` and publishes code with `Publish-AzWebApp`.
6. Validate schedules and exported files after deployment.

## Repository Layout

- `function/`: Azure Functions app (triggers, shared module, config).
- `function/Modules/Reporting/`: shared export orchestration and report collectors.
- `deploy/main.bicep`: infrastructure and app-settings source of truth.
- `deploy/1-provision-infra.ps1`: deploy infrastructure.
- `deploy/2-assign-graph-permissions.ps1`: assign required Graph app roles.
- `deploy/3-restore-function-modules.ps1`: restore PowerShell modules into `function/Modules`.
- `deploy/4-deploy-function-code.ps1`: code-only deployment (zip + `Publish-AzWebApp`).
- `deploy/deploy.ps1`: one-command full deployment.

## Prerequisites

- Azure subscription access with rights to deploy resource groups/resources.
- Global Administrator or Privileged Role Administrator for app-role assignment for managed identity.
- Az PowerShell modules (`Az.Accounts`, `Az.Resources`, `Az.Websites`, `Az.Storage`).
- Microsoft Graph PowerShell modules (`Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications`).

## Configuration Model

Runtime behavior is driven by `function/exports.config.json`.

| Key | Applies To | Description |
|---|---|---|
| `defaults` | Global | Shared defaults across reports (formats, storage). |
| `exports.<EXPORT_KEY>` | Per report | Per-export overrides and report settings. |

### Common Keys

| Key | Applies To | Description |
|---|---|---|
| `enabled` | All exports | Enables or disables the export. |
| `formats` | All exports | Output formats to generate (`json`, `csv`, `html`). |
| `blobPrefix` | All exports | Blob path prefix used for generated files. |
| `storage.storageAccount` | All exports | Target storage account for report output. |
| `storage.storageContainer` | All exports | Target blob container for report output. |
| `storage.storageConnectionString` | All exports (optional) | Optional explicit storage connection string override. |

### Report-Specific Keys

| Key | Applies To | Description |
|---|---|---|
| `groupIds` | `GROUPMEMBERS` | Group object IDs included in export scope. |
| `additionalProperties` | `GROUPMEMBERS`, `AUGROUPMEMBERS` | Extra user properties to include in output. |
| `excludeAdditionalPropertiesByGroup` | `GROUPMEMBERS`, `AUGROUPMEMBERS` | Per-group exclusions for additional properties. |
| `administrativeUnitIds` | `AUGROUPMEMBERS` | Administrative Unit IDs used to discover groups. |
| `expiryDays` | `APPREGS` | Credential expiry look-ahead window (days). |
| `lowAvailableThreshold` | `LICENSES` | Threshold for low license availability flagging. |
| `friendlyNamesSourceUrl` | `LICENSES` | Source URL for SKU friendly-name mapping data. |
| `mappingCacheHours` | `LICENSES` | Cache duration for friendly-name mapping data. |
| `days` | `INACTIVEADMINS` | Inactivity threshold in days for admin detection. |

## Deployment

One-command full deploy (Infra + Graph permissions + module restore + code publish):

```powershell
$fullDeployParams = @{
  SubscriptionId          = "<subscription-id>"
  ResourceGroupName       = "<resource-group>"
  Location                = "<location>"
  FunctionAppName         = "<function-app>"
  StorageAccountName      = "<runtime-storage-account>"
  ExportStorageAccountName = "<export-storage-account>"
}
pwsh ./deploy/deploy.ps1 @fullDeployParams
```

Manual deploy with full control over steps 1-4:

```powershell
# Step 1: Provision infrastructure
$deployParams = @{
  SubscriptionId           = "<subscription-id>"
  ResourceGroupName        = "<resource-group>"
  Location                 = "<location>"
  FunctionAppName          = "<function-app>"
  StorageAccountName       = "<runtime-storage-account>"
  ExportStorageAccountName = "<export-storage-account>"
}
pwsh ./deploy/1-provision-infra.ps1 @deployParams

# Step 2: Assign Graph app permissions
$setPermissionsParams = @{
  FunctionManagedIdentityObjectId = "00000000-0000-0000-0000-000000000000"
  TenantId                        = "00000000-0000-0000-0000-000000000000"
}
pwsh ./deploy/2-assign-graph-permissions.ps1 @setPermissionsParams

# Step 3: Restore function modules
pwsh ./deploy/3-restore-function-modules.ps1

# Step 4: Package and publish function code
$codeDeployParams = @{
  ResourceGroupName = "<resource-group>"
  FunctionAppName   = "<function-app>"
}
pwsh ./deploy/4-deploy-function-code.ps1 @codeDeployParams
```

Notes:
- `function/Modules/Az.*` and `function/Modules/Microsoft.Graph.*` are intentionally not committed and must be restored before code is published to the function.

## Report Catalog

| Function | Report Key | Purpose | Schedule App Setting |
|---|---|---|---|
| `ExportEntraRoles` | `ENTRAROLES` | Active + eligible Entra role assignments with resolved principal details. | `EXPORT_ENTRAROLES_SCHEDULE` |
| `ExportGroupMembers` | `GROUPMEMBERS` | Transitive user membership for configured groups. | `EXPORT_GROUPMEMBERS_SCHEDULE` |
| `ExportAuGroupMembers` | `AUGROUPMEMBERS` | Transitive user membership for groups inside configured Administrative Units. | `EXPORT_AUGROUPMEMBERS_SCHEDULE` |
| `ExportSubscriptions` | `SUBSCRIPTIONS` | Azure subscription inventory and normalized tags/policy fields. | `EXPORT_SUBSCRIPTIONS_SCHEDULE` |
| `ExportAppRegistrations` | `APPREGS` | App registration secret/cert credential expiry inventory. | `EXPORT_APPREGS_SCHEDULE` |
| `ExportGraphPermissions` | `GRAPHPERMS` | Graph app-permission grants on service principals and managed identities with risk flags. | `EXPORT_GRAPHPERMS_SCHEDULE` |
| `ExportLicenses` | `LICENSES` | Subscribed SKU usage/capacity and low availability detection. | `EXPORT_LICENSES_SCHEDULE` |
| `ExportInactiveAdmins` | `INACTIVEADMINS` | Privileged users with inactivity based on sign-in activity + threshold days. | `EXPORT_INACTIVEADMINS_SCHEDULE` |

Default schedule values are in `deploy/main.bicep` and use Azure Functions NCRONTAB (UTC).

## Storage Output Convention

Each report writes one or more files per run:

- Container: configured `storageContainer` (default `reports`)
- Blob path: `<blobPrefix>/<fileNameBase>_<yyyyMMdd_HHmmss>.<format>`
- Formats: `json`, `csv`, `html` (configurable per report)

## Troubleshooting

- `Connect-MgGraph -Identity` fails:
  - Confirm function managed identity is enabled.
  - Confirm required Graph app-role assignments are granted.
- Storage upload errors:
  - Confirm `Storage Blob Data Contributor` on export storage account.
  - Confirm container exists and storage account name is correct.
- Empty report output:
  - Confirm export `enabled` is `true` in `function/exports.config.json`.
  - Confirm scope settings (for example `groupIds`, `administrativeUnitIds`) point to valid objects.
- `SUBSCRIPTIONS` report missing data:
  - Confirm management group or subscription-level `Reader` role assignment for function managed identity.
- Invalid timer expressions:
  - Use six-field NCRONTAB in UTC for `EXPORT_*_SCHEDULE`.
