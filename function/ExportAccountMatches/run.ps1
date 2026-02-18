param($Timer)

$modulePath = Join-Path $PSScriptRoot "..\Modules\Reporting\Reporting.psd1"
Import-Module $modulePath -Force

if ($Timer.IsPastDue) {
    Write-Host "Timer trigger is running late."
}

$invocationStartedAtUtc = (Get-Date).ToUniversalTime()
Write-Host "[FunctionInvocation] exportGroup=ACCOUNTMATCH event=start utc=$($invocationStartedAtUtc.ToString('o')) isPastDue=$($Timer.IsPastDue)"

$exportNames = @(
    Get-ConfiguredExportNamesByPrefix -Prefix "ACCOUNTMATCH_"
)
if (@($exportNames).Count -eq 0) {
    Write-Warning "[FunctionInvocation] exportGroup=ACCOUNTMATCH event=no_exports_configured message='No exports.config.json entries found matching ACCOUNTMATCH_*'"
    return
}

foreach ($exportName in $exportNames) {
    $currentExportName = $exportName
    Invoke-Export -ExportName $currentExportName -FetchData { Get-AccountMatchesExport -ExportName $currentExportName }
}

Write-Host "[FunctionInvocation] exportGroup=ACCOUNTMATCH event=end utc=$(((Get-Date).ToUniversalTime()).ToString('o')) exportCount=$(@($exportNames).Count)"
