# Getting Started

This page is for a first-time setup from clone to first successful export.

## Prerequisites

You need:

- Azure subscription access to deploy resources
- Permission to assign Microsoft Graph app roles to the Function App managed identity
- PowerShell 7+
- Az PowerShell modules
- Microsoft Graph PowerShell modules

## Clone and review

```powershell
git clone https://github.com/Hardstl/TenantPulse.git
cd TenantPulse
```

Check the key files:

- `function/exports.config.json`
- `deploy/main.bicep`
- `deploy/deploy.ps1`

## Configure exports

Edit `function/exports.config.json`:

- Set `defaults.storage.storageAccount`
- Set `defaults.storage.storageContainer`
- Enable only exports you want
- Add scope values like `groupIds` / `administrativeUnitIds`
- For account matching, add one or more `ACCOUNTMATCH_*` entries

## Set schedule defaults (optional)

In `deploy/main.bicep`, set UTC NCRONTAB defaults:

- `entraRoleMembersSchedule`
- `accountMatchSchedule`
- `groupMembersSchedule`
- `auGroupMembersSchedule`
- `subscriptionsSchedule`
- `appRegistrationsSchedule`
- `graphPermissionsSchedule`
- `licensesSchedule`
- `inactiveEntraAdminsSchedule`

## Deploy

Full deployment:

```powershell
$fullDeployParams = @{
  SubscriptionId = "<subscription-id>"
  ResourceGroupName = "<resource-group>"
  Location = "<location>"
  FunctionAppName = "<function-app-name>"
  StorageAccountName = "<runtime-storage-account>"
  ExportStorageAccountName = "<export-storage-account>"
}
pwsh ./deploy/deploy.ps1 @fullDeployParams
```

## First verification

1. Confirm app settings exist:

```powershell
$appSettings = (Get-AzWebApp -ResourceGroupName "<resource-group>" -Name "<function-app-name>").SiteConfig.AppSettings
$appSettings |
  Where-Object { $_.Name -like "EXPORT_*" } |
  Select-Object Name, Value |
  Format-Table -AutoSize
```

2. Trigger one function manually and check blobs.

3. Confirm files are written under `<blobPrefix>/<name>_<timestamp>.<format>`.

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Deployment](Deployment.md)
- [Troubleshooting](Troubleshooting.md)
