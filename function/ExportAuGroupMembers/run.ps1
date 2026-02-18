param($Timer)

$modulePath = Join-Path $PSScriptRoot "..\Modules\Reporting\Reporting.psd1"
Import-Module $modulePath -Force

if ($Timer.IsPastDue) {
    Write-Host "Timer trigger is running late."
}

$invocationStartedAtUtc = (Get-Date).ToUniversalTime()
Write-Host "[FunctionInvocation] export=AUGROUPMEMBERS event=start utc=$($invocationStartedAtUtc.ToString('o')) isPastDue=$($Timer.IsPastDue)"
Invoke-Export -ExportName "AUGROUPMEMBERS" -FetchData { Get-AuGroupMembersExport }
Write-Host "[FunctionInvocation] export=AUGROUPMEMBERS event=end utc=$(((Get-Date).ToUniversalTime()).ToString('o'))"

