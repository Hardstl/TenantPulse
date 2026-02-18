param($Timer)

$modulePath = Join-Path $PSScriptRoot "..\Modules\Reporting\Reporting.psd1"
Import-Module $modulePath -Force

if ($Timer.IsPastDue) {
    Write-Host "Timer trigger is running late."
}

$invocationStartedAtUtc = (Get-Date).ToUniversalTime()
Write-Host "[FunctionInvocation] export=SUBSCRIPTIONS event=start utc=$($invocationStartedAtUtc.ToString('o')) isPastDue=$($Timer.IsPastDue)"
Invoke-Export -ExportName "SUBSCRIPTIONS" -FetchData { Get-SubscriptionsExport }
Write-Host "[FunctionInvocation] export=SUBSCRIPTIONS event=end utc=$(((Get-Date).ToUniversalTime()).ToString('o'))"

