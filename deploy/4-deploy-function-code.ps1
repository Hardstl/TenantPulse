param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$FunctionAppName,

    [string]$FunctionRoot = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\function')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FunctionRoot)) {
    throw "Function root '$FunctionRoot' not found."
}

$resolvedFunctionRoot = (Resolve-Path $FunctionRoot).Path
$zipPath = Join-Path (Split-Path -Parent $resolvedFunctionRoot) 'function.zip'
Write-Host ("[CodeDeploy] Starting code deployment for function app '{0}'" -f $FunctionAppName)
Write-Host ("[CodeDeploy] Resolved function root: '{0}'" -f $resolvedFunctionRoot)
Write-Host ("[CodeDeploy] Package path: '{0}'" -f $zipPath)

if (Test-Path -LiteralPath $zipPath) {
    Write-Host ("[CodeDeploy] Removing existing package '{0}'" -f $zipPath)
    Remove-Item -LiteralPath $zipPath -Force
}

Write-Host ("[CodeDeploy] Packaging function content from '{0}' to '{1}'" -f $resolvedFunctionRoot, $zipPath)
Compress-Archive -Path (Join-Path $resolvedFunctionRoot '*') -DestinationPath $zipPath -Force

Write-Host "[CodeDeploy] Validating Publish-AzWebApp availability"
$publishCmd = Get-Command -Name Publish-AzWebApp -ErrorAction SilentlyContinue
if (-not $publishCmd) {
    throw "Publish-AzWebApp cmdlet not found. Install/import Az.Websites before deploying function code."
}

Write-Host ("[CodeDeploy] Publishing package to Function App '{0}' in resource group '{1}'" -f $FunctionAppName, $ResourceGroupName)
Publish-AzWebApp `
    -ResourceGroupName $ResourceGroupName `
    -Name $FunctionAppName `
    -ArchivePath $zipPath `
    -Force | Out-Null

Write-Host ("[CodeDeploy] Code deployment completed for function app '{0}'" -f $FunctionAppName)
