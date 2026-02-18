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
    [string]$ExportStorageAccountName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraPath = Join-Path $scriptRoot 'main.bicep'

Write-Host ("[Infra] Starting infrastructure deployment for function app '{0}' in resource group '{1}' ({2})" -f $FunctionAppName, $ResourceGroupName, $Location)
Write-Host "[Infra] Connecting to Azure"
Connect-AzAccount -SubscriptionId $SubscriptionId

Write-Host ("[Infra] Setting Azure context to subscription '{0}'" -f $SubscriptionId)
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

Write-Host ("[Infra] Ensuring resource group '{0}' exists in '{1}'" -f $ResourceGroupName, $Location)
New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force | Out-Null

Write-Host ("[Infra] Deploying template '{0}'" -f $infraPath)
$deploymentParams = @{
    ResourceGroupName         = $ResourceGroupName
    TemplateFile              = $infraPath
    functionAppName           = $FunctionAppName
    storageAccountName        = $StorageAccountName
    exportStorageAccountName  = $ExportStorageAccountName
    location                  = $Location
}
New-AzResourceGroupDeployment @deploymentParams | Out-Null
Write-Host ("[Infra] Infrastructure deployment completed for '{0}'" -f $FunctionAppName)
