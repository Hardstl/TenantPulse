[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$FunctionAppUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Code,

    [string[]]$FunctionNames,

    [string]$FunctionRoot = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\function'),

    [ValidateRange(5, 1800)]
    [int]$TimeoutSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($null -eq $FunctionNames -or $FunctionNames.Count -eq 0) {
    if (-not (Test-Path -LiteralPath $FunctionRoot)) {
        throw "Function root '$FunctionRoot' was not found. Provide -FunctionNames explicitly or set -FunctionRoot."
    }

    $functionDirectories = Get-ChildItem -LiteralPath $FunctionRoot -Directory -ErrorAction Stop
    $FunctionNames = @(
        $functionDirectories |
            Where-Object {
                Test-Path -LiteralPath (Join-Path $_.FullName 'function.json')
            } |
            Select-Object -ExpandProperty Name
    )

    if ($FunctionNames.Count -eq 0) {
        throw "No functions found under '$FunctionRoot'. Expected subfolders that contain function.json."
    }
}

$normalizedFunctionNames = @(
    $FunctionNames |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Sort-Object -Unique
)

if ($normalizedFunctionNames.Count -eq 0) {
    throw 'No valid function names were supplied.'
}

$baseUrl = $FunctionAppUrl.TrimEnd('/')
$results = @()

foreach ($functionName in $normalizedFunctionNames) {
    $invokeUrl = "$baseUrl/admin/functions/$functionName"
    $actionDescription = "Invoke function '$functionName' via '$invokeUrl'"

    if (-not $PSCmdlet.ShouldProcess($functionName, $actionDescription)) {
        $results += [pscustomobject]@{
            FunctionName = $functionName
            Status       = 'Skipped'
            Url          = $invokeUrl
            Message      = 'Skipped by WhatIf/Confirm.'
            Response     = $null
        }
        continue
    }

    try {
        $headers = @{
            'x-functions-key' = $Code
        }

        $body = @{
            input = @{}
        } | ConvertTo-Json -Depth 5

        $invokeRestMethodParams = @{
            Uri         = $invokeUrl
            Method      = 'Post'
            Headers     = $headers
            Body        = $body
            ContentType = 'application/json'
            TimeoutSec  = $TimeoutSec
            ErrorAction = 'Stop'
        }

        $response = Invoke-RestMethod @invokeRestMethodParams
        Write-Information "Invoked '$functionName' successfully."

        $results += [pscustomobject]@{
            FunctionName = $functionName
            Status       = 'Succeeded'
            Url          = $invokeUrl
            Message      = 'Invocation accepted.'
            Response     = $response
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Warning "Failed to invoke '$functionName': $message"

        $results += [pscustomobject]@{
            FunctionName = $functionName
            Status       = 'Failed'
            Url          = $invokeUrl
            Message      = $message
            Response     = $null
        }
    }
}

$successCount = @($results | Where-Object { $_.Status -eq 'Succeeded' }).Count
$failureCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
$skippedCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count

Write-Host ("[InvokeFunctions] Completed. Succeeded={0} Failed={1} Skipped={2}" -f $successCount, $failureCount, $skippedCount)

$results
