param($Timer)

$modulePath = Join-Path $PSScriptRoot "..\Modules\Reporting\Reporting.psd1"
Import-Module $modulePath -Force

if ($Timer.IsPastDue) {
    Write-Host "Timer trigger is running late."
}

$invocationStartedAtUtc = (Get-Date).ToUniversalTime()
Write-Host "[FunctionInvocation] export=GRAPHPERMS event=start utc=$($invocationStartedAtUtc.ToString('o')) isPastDue=$($Timer.IsPastDue)"
Invoke-Export -ExportName "GRAPHPERMS" -FetchData { Get-GraphPermissionsExport }
Write-Host "[FunctionInvocation] export=GRAPHPERMS event=end utc=$(((Get-Date).ToUniversalTime()).ToString('o'))"

