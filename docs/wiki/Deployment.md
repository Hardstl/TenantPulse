# Deployment

This page covers deployment options and verification.

## Required permissions

Before running deployment commands, make sure your identity has:

- `Owner` or `User Access Administrator` and `Contributor` on the subscription.
- `Global Administrator` or `Privileged Role Administrator` in Entra.

## Option 1: Full scripted deployment

```powershell
$fullDeployParams = @{
  SubscriptionId = "<subscription-id>"
  ResourceGroupName = "<resource-group>"
  Location = "<location>"
  FunctionAppName = "<function-app>"
  StorageAccountName = "<runtime-storage-account>"
  ExportStorageAccountName = "<export-storage-account>"
}
pwsh ./deploy/deploy.ps1 @fullDeployParams
```

This runs:

1. Infra provisioning
2. Graph permission assignment
3. Module restore
4. Function code publish

## Option 2: Step-by-step scripts

Step 1: Provision infrastructure

```powershell
$infraParams = @{
  SubscriptionId = "<subscription-id>"
  ResourceGroupName = "<resource-group>"
  Location = "<location>"
  FunctionAppName = "<function-app>"
  StorageAccountName = "<runtime-storage-account>"
  ExportStorageAccountName = "<export-storage-account>"
}
pwsh ./deploy/1-provision-infra.ps1 @infraParams
```

Step 2: Assign Graph app permissions to the function managed identity

```powershell
$graphPermissionParams = @{
  FunctionManagedIdentityObjectId = "<function-managed-identity-object-id>"
  TenantId = "<tenant-id>"
}
pwsh ./deploy/2-assign-graph-permissions.ps1 @graphPermissionParams
```

Step 3: Restore function modules

```powershell
pwsh ./deploy/3-restore-function-modules.ps1
```

Step 4: Deploy function code

```powershell
$codeDeployParams = @{
  ResourceGroupName = "<resource-group>"
  FunctionAppName = "<function-app>"
}
pwsh ./deploy/4-deploy-function-code.ps1 @codeDeployParams
```

## Related pages

- [Getting Started](Getting-Started.md)