param(
    [string]$FunctionRoot = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\function'),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulesPath = Join-Path $FunctionRoot 'Modules'
if (-not (Test-Path -LiteralPath $FunctionRoot)) {
    throw "Function root '$FunctionRoot' not found."
}

if (-not (Test-Path -LiteralPath $modulesPath)) {
    Write-Host ("[Modules] Creating modules directory '{0}'" -f $modulesPath)
    New-Item -Path $modulesPath -ItemType Directory -Force | Out-Null
}

$requiredModules = @(
    'Az.Accounts',
    'Az.ResourceGraph',
    'Az.Storage',
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DirectoryObjects',
    'Microsoft.Graph.Identity.Governance',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Users'
)

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # Ignore if runtime controls TLS protocol selection.
}

Write-Host ("[Modules] Starting module restore to '{0}'" -f $modulesPath)
foreach ($moduleName in $requiredModules) {
    $saveParams = @{
        Name         = $moduleName
        Path         = $modulesPath
        Repository   = 'PSGallery'
        Force        = $true
        ErrorAction  = 'Stop'
    }

    if ($Force) {
        $saveParams['AcceptLicense'] = $true
    }

    Write-Host ("[Modules] Saving module '{0}' (latest)" -f $moduleName)
    Save-Module @saveParams
}

Write-Host "[Modules] Verifying restored modules"
$missingModules = @()
foreach ($moduleName in $requiredModules) {
    $modulePath = Join-Path $modulesPath $moduleName
    if (-not (Test-Path -LiteralPath $modulePath)) {
        $missingModules += $moduleName
    }
}

if ($missingModules.Count -gt 0) {
    throw ("Module restore incomplete. Missing: {0}" -f ($missingModules -join ', '))
}

Write-Host ("[Modules] Restore completed. Restored {0} modules into '{1}'" -f $requiredModules.Count, $modulesPath)
