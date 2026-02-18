param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Location,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$FunctionAppName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$ExportStorageAccountName,

    [string]$FunctionRoot = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\function')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraDeployScriptPath = Join-Path $scriptRoot '1-provision-infra.ps1'
$setPermissionsScriptPath = Join-Path $scriptRoot '2-assign-graph-permissions.ps1'
$restoreScriptPath = Join-Path $scriptRoot '3-restore-function-modules.ps1'
$deployCodeScriptPath = Join-Path $scriptRoot '4-deploy-function-code.ps1'

foreach ($requiredScript in @($infraDeployScriptPath, $restoreScriptPath, $deployCodeScriptPath, $setPermissionsScriptPath)) {
    if (-not (Test-Path -LiteralPath $requiredScript)) {
        throw "Required script '$requiredScript' not found."
    }
}

Write-Host ("[FullDeploy] Starting full deployment for function app '{0}' in resource group '{1}' ({2})" -f $FunctionAppName, $ResourceGroupName, $Location)
Write-Host "[FullDeploy] Step 1/4 [Infra] Deploying infrastructure"
& $infraDeployScriptPath `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -FunctionAppName $FunctionAppName `
    -StorageAccountName $StorageAccountName `
    -ExportStorageAccountName $ExportStorageAccountName

Write-Host "[FullDeploy] Step 2/4 [GraphPermissions] Configuring Graph app permissions"
Write-Host ("[FullDeploy] [GraphPermissions] Setting subscription context to '{0}'" -f $SubscriptionId)
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
$context = Get-AzContext
$tenantId = [string]$context.Tenant.Id
Write-Host ("[FullDeploy] [GraphPermissions] Resolving function app identity for '{0}'" -f $FunctionAppName)
$functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop
$functionManagedIdentityObjectId = [string]$functionApp.Identity.PrincipalId
if ([string]::IsNullOrWhiteSpace($functionManagedIdentityObjectId)) {
    throw "Function app '$FunctionAppName' has no system-assigned managed identity principal id."
}

$permissionsConfigured = $false
try {
    & $setPermissionsScriptPath `
        -FunctionManagedIdentityObjectId $functionManagedIdentityObjectId `
        -TenantId $tenantId | Out-Null
    $permissionsConfigured = $true
    Write-Host "[FullDeploy] [GraphPermissions] Permission configuration succeeded"
} catch {
    if ($_.Exception.Message -match 'Missing required PowerShell module\(s\)') {
        Write-Warning "[FullDeploy] [GraphPermissions] Graph modules not available in current session. Permissions will be retried after module restore."
    } else {
        throw
    }
}

Write-Host "[FullDeploy] Step 3/4 [Modules] Restoring function modules"
& $restoreScriptPath -FunctionRoot $FunctionRoot

$modulesPath = (Resolve-Path (Join-Path $FunctionRoot 'Modules')).Path
$pathSeparator = [System.IO.Path]::PathSeparator
$modulePaths = @($env:PSModulePath -split [regex]::Escape($pathSeparator))
if ($modulePaths -notcontains $modulesPath) {
    Write-Host ("[FullDeploy] [Modules] Prepending '{0}' to PSModulePath" -f $modulesPath)
    $env:PSModulePath = "$modulesPath$pathSeparator$env:PSModulePath"
}

if (-not $permissionsConfigured) {
    Write-Host "[FullDeploy] [GraphPermissions] Retrying permission configuration using restored modules"
    & $setPermissionsScriptPath `
        -FunctionManagedIdentityObjectId $functionManagedIdentityObjectId `
        -TenantId $tenantId | Out-Null
    Write-Host "[FullDeploy] [GraphPermissions] Permission configuration succeeded on retry"
}

Write-Host "[FullDeploy] Step 4/4 [CodeDeploy] Publishing function code"
& $deployCodeScriptPath `
    -ResourceGroupName $ResourceGroupName `
    -FunctionAppName $FunctionAppName `
    -FunctionRoot $FunctionRoot

Write-Host ("[FullDeploy] Full deployment completed for function app '{0}'" -f $FunctionAppName)
