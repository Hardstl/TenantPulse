Set-StrictMode -Version Latest

function Get-EnvVar {
    <#
    .SYNOPSIS
    Gets an environment variable value with an optional default.
    Used to safely read optional runtime settings without repeating null/whitespace checks.

    .EXAMPLE
    Get-EnvVar -Name 'EXPORT_SUBSCRIPTIONS_SCHEDULE' -Default '0 0 4 * * 0'
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Default = $null
    )
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value
}

$script:ExportConfigCache = $null
$script:CurrentExportRunContext = $null

function New-ExportRunId {
    <#
    .SYNOPSIS
    Creates a correlation id for an export run.
    #>
    return [guid]::NewGuid().ToString('N')
}

function Set-ExportRunContext {
    <#
    .SYNOPSIS
    Sets run context used by runtime logging helpers.
    #>
    param(
        [Parameter(Mandatory)][string]$ExportName,
        [Parameter(Mandatory)][string]$RunId
    )
    $script:CurrentExportRunContext = [PSCustomObject]@{
        ExportName = $ExportName
        RunId = $RunId
    }
}

function Clear-ExportRunContext {
    <#
    .SYNOPSIS
    Clears run context used by runtime logging helpers.
    #>
    $script:CurrentExportRunContext = $null
}

function Write-ExportRuntimeLog {
    <#
    .SYNOPSIS
    Writes a structured runtime log line for export execution.
    #>
    param(
        [AllowNull()][string]$ExportName = $null,
        [AllowNull()][string]$RunId = $null,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Event,
        [ValidateSet('ok', 'warn', 'error')]
        [string]$Status = 'ok',
        [AllowNull()][hashtable]$Data = $null
    )

    if ([string]::IsNullOrWhiteSpace($ExportName) -and $null -ne $script:CurrentExportRunContext) {
        $ExportName = [string]$script:CurrentExportRunContext.ExportName
    }
    if ([string]::IsNullOrWhiteSpace($RunId) -and $null -ne $script:CurrentExportRunContext) {
        $RunId = [string]$script:CurrentExportRunContext.RunId
    }

    if ([string]::IsNullOrWhiteSpace($ExportName)) { $ExportName = 'UNKNOWN' }
    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = 'none' }

    $parts = @(
        '[ExportRuntime]',
        "export=$ExportName",
        "runId=$RunId",
        "stage=$Stage",
        "event=$Event",
        "status=$Status"
    )

    if ($Data -and $Data.Count -gt 0) {
        foreach ($key in @($Data.Keys | Sort-Object)) {
            $value = $Data[$key]
            if ($null -eq $value) {
                $value = ''
            } else {
                $value = $value.ToString()
            }
            $value = $value -replace '\s+', ' '
            $parts += "$key=$value"
        }
    }

    $line = ($parts -join ' ')
    switch ($Status) {
        'warn' { Write-Warning $line }
        'error' { Write-Error $line }
        default { Write-Host $line }
    }
}

function Get-ElapsedMilliseconds {
    <#
    .SYNOPSIS
    Gets elapsed milliseconds from a start time.
    #>
    param([Parameter(Mandatory)][datetime]$StartedAtUtc)
    return [math]::Round(((Get-Date).ToUniversalTime() - $StartedAtUtc).TotalMilliseconds)
}

function Get-ObjectPropertyValue {
    <#
    .SYNOPSIS
    Safely gets a named property from hashtables and objects.
    Normalizes access across Graph SDK objects, hashtables, and AdditionalProperties payloads.

    .EXAMPLE
    Get-ObjectPropertyValue -InputObject @{ name = 'SUBSCRIPTIONS' } -Name 'name'
    #>
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name
    )
    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [hashtable]) {
        if ($InputObject.ContainsKey($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }
    if ($InputObject.PSObject.Properties.Name -contains 'AdditionalProperties') {
        $additional = $InputObject.AdditionalProperties
        if ($additional -and $additional.ContainsKey($Name)) {
            return $additional[$Name]
        }
    }
    return $null
}

function Test-HasUsableValue {
    <#
    .SYNOPSIS
    Checks whether a value is non-null and non-empty.
    Used by setting/conversion helpers so blank values fall back instead of being treated as configured.

    .EXAMPLE
    Test-HasUsableValue -Value 'enabled'
    #>
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }
    return $true
}

function ConvertTo-BooleanValue {
    <#
    .SYNOPSIS
    Converts common truthy and falsy values to a boolean.
    Ensures string values like true/1/yes and false/0/no are interpreted consistently with safe defaults.

    .EXAMPLE
    ConvertTo-BooleanValue -Value 'true' -Default $false
    #>
    param(
        [AllowNull()][object]$Value,
        [bool]$Default = $false
    )
    if (-not (Test-HasUsableValue -Value $Value)) {
        return $Default
    }
    if ($Value -is [bool]) {
        return $Value
    }

    $raw = $Value.ToString().Trim().ToLowerInvariant()
    switch ($raw) {
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'y' { return $true }
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
        'n' { return $false }
        default { return $Default }
    }
}

function ConvertTo-IntValue {
    <#
    .SYNOPSIS
    Converts a value to int with default and minimum checks.
    Prevents invalid numeric settings from breaking report logic by applying guarded fallback behavior.

    .EXAMPLE
    ConvertTo-IntValue -Value '24' -Default 12 -MinValue 1
    #>
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][int]$Default,
        [int]$MinValue = [int]::MinValue
    )
    if (-not (Test-HasUsableValue -Value $Value)) {
        return $Default
    }
    $parsed = 0
    if (-not [int]::TryParse($Value.ToString(), [ref]$parsed)) {
        return $Default
    }
    if ($parsed -lt $MinValue) {
        return $Default
    }
    return $parsed
}

function ConvertTo-NormalizedStringList {
    <#
    .SYNOPSIS
    Normalizes input values into a trimmed unique string list.
    Used for list settings so CSV and array input formats are handled the same way.

    .EXAMPLE
    ConvertTo-NormalizedStringList -InputValues @('json,csv',' html ') -SplitCsv
    #>
    param(
        [AllowNull()]
        [object[]]$InputValues,
        [switch]$SplitCsv
    )

    $values = @()
    foreach ($item in @($InputValues)) {
        if (-not (Test-HasUsableValue -Value $item)) {
            continue
        }
        if ($item -is [string] -and $SplitCsv) {
            $values += $item.Split(',')
        } else {
            $values += $item.ToString()
        }
    }

    return @(
        $values |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
}

function Get-ExportConfigFile {
    <#
    .SYNOPSIS
    Loads, validates, caches, and returns export configuration.
    Centralizes file read/JSON parse/shape validation so downstream functions consume a trusted config object.

    .EXAMPLE
    Get-ExportConfigFile
    #>
    if ($null -ne $script:ExportConfigCache) {
        return $script:ExportConfigCache
    }

    $functionRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $configFilePath = Join-Path $functionRoot 'exports.config.json'
    if (-not (Test-Path -LiteralPath $configFilePath -PathType Leaf)) {
        throw "exports.config.json not found at '$configFilePath'. Include it in the function package root."
    }
    try {
        $json = Get-Content -LiteralPath $configFilePath -Raw -ErrorAction Stop
    } catch {
        throw "Failed reading exports config file '$configFilePath': $($_.Exception.Message)"
    }

    try {
        $config = ConvertFrom-Json -InputObject $json -AsHashtable -Depth 20
    } catch {
        throw "exports.config.json is invalid JSON: $($_.Exception.Message)"
    }

    if (-not ($config -is [hashtable])) {
        throw "exports.config.json must deserialize to a JSON object."
    }

    if (-not ($config.ContainsKey('exports') -and ($config['exports'] -is [hashtable]))) {
        throw "exports.config.json must contain an 'exports' object."
    }

    if (-not $config.ContainsKey('defaults') -or -not ($config['defaults'] -is [hashtable])) {
        $config['defaults'] = @{}
    }

    $script:ExportConfigCache = $config
    return $script:ExportConfigCache
}

function Get-ExportConfig {
    <#
    .SYNOPSIS
    Gets the configuration object for a specific export.
    Provides per-export validation so callers fail fast when a section is missing or malformed.

    .EXAMPLE
    Get-ExportConfig -ExportName 'SUBSCRIPTIONS'
    #>
    param([Parameter(Mandatory)][string]$ExportName)

    $config = Get-ExportConfigFile
    $exportNameUpper = $ExportName.ToUpperInvariant()
    if (-not $config['exports'].ContainsKey($exportNameUpper)) {
        throw "exports.config.json exports.$exportNameUpper is missing."
    }

    $exportConfig = $config['exports'][$exportNameUpper]
    if (-not ($exportConfig -is [hashtable])) {
        throw "exports.config.json exports.$exportNameUpper must be an object."
    }

    return $exportConfig
}

function Get-ConfiguredExportNamesByPrefix {
    <#
    .SYNOPSIS
    Gets configured export names that start with a specific prefix.
    Supports grouped export patterns where multiple exports share collector logic.

    .EXAMPLE
    Get-ConfiguredExportNamesByPrefix -Prefix 'ACCOUNTMATCH_'
    #>
    param([Parameter(Mandatory)][string]$Prefix)

    $normalizedPrefix = $Prefix.Trim().ToUpperInvariant()
    $config = Get-ExportConfigFile
    return @(
        @($config['exports'].Keys) |
            ForEach-Object { [string]$_ } |
            Where-Object { $_.ToUpperInvariant().StartsWith($normalizedPrefix, [System.StringComparison]::Ordinal) } |
            Sort-Object
    )
}

function Get-ExportSetting {
    <#
    .SYNOPSIS
    Resolves an export setting with defaults and optional required enforcement.
    Enables export-level overrides while inheriting defaults, reducing duplicated config.

    .EXAMPLE
    Get-ExportSetting -ExportName 'SUBSCRIPTIONS' -Name 'blobPrefix'
    #>
    param(
        [Parameter(Mandatory)][string]$ExportName,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Section = $null,
        [AllowNull()][object]$Default = $null,
        [switch]$Required
    )

    $config = Get-ExportConfigFile
    $exportConfig = Get-ExportConfig -ExportName $ExportName

    if (-not [string]::IsNullOrWhiteSpace($Section) -and
        $exportConfig.ContainsKey($Section) -and
        ($exportConfig[$Section] -is [hashtable])) {
        $sectionObject = $exportConfig[$Section]
        if ($sectionObject.ContainsKey($Name) -and (Test-HasUsableValue -Value $sectionObject[$Name])) {
            return $sectionObject[$Name]
        }
    }

    if ($exportConfig.ContainsKey($Name) -and (Test-HasUsableValue -Value $exportConfig[$Name])) {
        return $exportConfig[$Name]
    }

    if (-not [string]::IsNullOrWhiteSpace($Section) -and
        $config['defaults'].ContainsKey($Section) -and
        ($config['defaults'][$Section] -is [hashtable])) {
        $sectionDefaults = $config['defaults'][$Section]
        if ($sectionDefaults.ContainsKey($Name) -and (Test-HasUsableValue -Value $sectionDefaults[$Name])) {
            return $sectionDefaults[$Name]
        }
    }

    if ($config['defaults'].ContainsKey($Name) -and (Test-HasUsableValue -Value $config['defaults'][$Name])) {
        return $config['defaults'][$Name]
    }

    if ($Required) {
        if ([string]::IsNullOrWhiteSpace($Section)) {
            throw "exports.config.json for '$ExportName' is missing required setting '$Name'."
        }
        throw "exports.config.json for '$ExportName' is missing required setting '$Section.$Name'."
    }

    return $Default
}

function Get-ExportIntSetting {
    <#
    .SYNOPSIS
    Gets an export setting and converts it to an integer.
    Combines setting resolution with numeric validation for concise, safe numeric option handling.

    .EXAMPLE
    Get-ExportIntSetting -ExportName 'LICENSES' -Name 'lowAvailableThreshold' -Default 5 -MinValue 0
    #>
    param(
        [Parameter(Mandatory)][string]$ExportName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Default,
        [int]$MinValue = [int]::MinValue
    )
    $value = Get-ExportSetting -ExportName $ExportName -Name $Name -Default $Default
    return ConvertTo-IntValue -Value $value -Default $Default -MinValue $MinValue
}

function Test-ExportEnabled {
    <#
    .SYNOPSIS
    Determines whether an export is enabled.
    Reads enabled from config and calls ConvertTo-BooleanValue so values like true/1 enable exports while missing or invalid values safely fall back.

    .EXAMPLE
    Test-ExportEnabled -ExportName 'SUBSCRIPTIONS'
    #>
    param([string]$ExportName)
    $enabled = Get-ExportSetting -ExportName $ExportName -Name 'enabled' -Default $false
    return ConvertTo-BooleanValue -Value $enabled -Default $false
}

function Get-ExportFormats {
    <#
    .SYNOPSIS
    Gets the allowed output formats for an export.
    Normalizes and filters configured formats to supported values (json/csv/html) with a safe default.

    .EXAMPLE
    Get-ExportFormats -ExportName 'SUBSCRIPTIONS'
    #>
    param([string]$ExportName)
    $rawFormats = Get-ExportSetting -ExportName $ExportName -Name 'formats' -Default @('json')
    $formatValues = @()

    if ($rawFormats -is [string]) {
        $formatValues = $rawFormats.Split(',')
    } else {
        $formatValues = @($rawFormats)
    }

    $formats = @(
        $formatValues |
            ForEach-Object { $_.ToString().Trim().ToLowerInvariant() } |
            Where-Object { $_ }
    )
    $allowed = @('json', 'csv', 'html')
    $formats = $formats | Where-Object { $allowed -contains $_ } | Select-Object -Unique
    if (-not $formats) {
        return @('json')
    }
    return $formats
}

function Get-StorageConfig {
    <#
    .SYNOPSIS
    Builds storage configuration for an export.
    Aggregates storage account/container/prefix settings so writers use one consistent config object.

    .EXAMPLE
    Get-StorageConfig -ExportName 'SUBSCRIPTIONS'
    #>
    param([string]$ExportName)
    return [PSCustomObject]@{
        StorageAccount   = Get-ExportSetting -ExportName $ExportName -Section 'storage' -Name 'storageAccount'
        StorageContainer = Get-ExportSetting -ExportName $ExportName -Section 'storage' -Name 'storageContainer'
        BlobPrefix       = Get-ExportSetting -ExportName $ExportName -Name 'blobPrefix' -Default $ExportName.ToLowerInvariant()
        ConnectionString = Get-ExportSetting -ExportName $ExportName -Section 'storage' -Name 'storageConnectionString'
    }
}

function Connect-ToMicrosoftGraph {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph using managed identity.
    Wraps Graph managed identity auth with structured logging and standardized error handling for export collectors.

    .EXAMPLE
    Connect-ToMicrosoftGraph
    #>
    [CmdletBinding()]
    param()

    $hasIdentityEndpoint = -not [string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT)
    $managedIdentityAvailable = $hasIdentityEndpoint
    $hasConnectMgGraph = $null -ne (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)

    $startMessage = ("[GraphAuth] Start managedIdentityAvailable={0}; " +
        "signal(identityEndpoint={1}); hasConnectMgGraph={2}") -f $managedIdentityAvailable, $hasIdentityEndpoint, $hasConnectMgGraph
    Write-Host $startMessage

    try {
        if (-not $managedIdentityAvailable) {
            Write-Warning "[GraphAuth] Managed identity requested but IDENTITY_ENDPOINT signal was not found."
        }
        Write-Host '[GraphAuth] Connecting to Microsoft Graph using Managed Identity...'
        Connect-MgGraph -Identity -ErrorAction Stop | Out-Null
        Write-Host "[GraphAuth] Connected to Microsoft Graph (Managed Identity)."
        return $true
    } catch {
        $message = $_.Exception.Message
        $mgContext = Get-MgContext -ErrorAction SilentlyContinue
        $contextSummary = if ($null -ne $mgContext) {
            "tenantId=$($mgContext.TenantId); account=$($mgContext.Account); authType=$($mgContext.AuthType)"
        } else {
            "none"
        }
        Write-Error "[GraphAuth] Connect-ToMicrosoftGraph failed. message=$message; context=$contextSummary"
        throw
    }
}

function ConvertTo-NullableUtcDateTime {
    <#
    .SYNOPSIS
    Converts a value to a nullable UTC DateTime.
    Used when parsing optional Graph date fields so invalid/missing values do not throw.

    .EXAMPLE
    ConvertTo-NullableUtcDateTime -Value '2026-02-13T04:00:00Z'
    #>
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        return $null
    }
    $raw = $Value.ToString()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($raw, [ref]$parsed)) {
        return $parsed.UtcDateTime
    }
    return $null
}

function Get-LatestDateTime {
    <#
    .SYNOPSIS
    Returns the latest DateTime value from a set.
    Supports fallback logic where multiple sign-in timestamps may exist and the newest should win.

    .EXAMPLE
    Get-LatestDateTime -Values @([datetime]'2026-01-01',[datetime]'2026-02-01')
    #>
    param([object[]]$Values)
    $latest = $null
    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }
        $candidate = $value
        if ($candidate -isnot [datetime]) {
            $candidate = ConvertTo-NullableUtcDateTime -Value $candidate
        }
        if ($null -eq $candidate) {
            continue
        }
        if ($null -eq $latest -or $candidate -gt $latest) {
            $latest = $candidate
        }
    }
    return $latest
}

function Get-LicenseFriendlyNameMap {
    <#
    .SYNOPSIS
    Builds a license SKU-to-friendly-name lookup map.
    Downloads/caches mapping data so license exports can show readable product names.

    .EXAMPLE
    Get-LicenseFriendlyNameMap
    #>
    $defaultCsvUrl = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
    $csvUrl = [string](Get-ExportSetting -ExportName 'LICENSES' -Name 'friendlyNamesSourceUrl' -Default $defaultCsvUrl)
    $cacheHours = 24
    $cachePath = Join-Path ([System.IO.Path]::GetTempPath()) 'export-license-map.csv'

    $downloadRequired = $true
    if (Test-Path $cachePath) {
        $age = (Get-Date).ToUniversalTime() - (Get-Item -Path $cachePath).LastWriteTimeUtc
        if ($age.TotalHours -lt $cacheHours) {
            $downloadRequired = $false
        }
    }

    if ($downloadRequired) {
        try {
            $tempPath = "$cachePath.tmp"
            Invoke-WebRequest -Uri $csvUrl -OutFile $tempPath -ErrorAction Stop | Out-Null
            Move-Item -Path $tempPath -Destination $cachePath -Force
        } catch {
            Write-Warning "License mapping download failed from '$csvUrl': $($_.Exception.Message)"
        }
    }

    $bySkuId = @{}
    $bySkuPartNumber = @{}
    if (-not (Test-Path $cachePath)) {
        return [PSCustomObject]@{
            BySkuId = $bySkuId
            BySkuPartNumber = $bySkuPartNumber
        }
    }

    try {
        $rows = Import-Csv -Path $cachePath -ErrorAction Stop
        foreach ($row in $rows) {
            $friendlyName = $row.Product_Display_Name
            if ([string]::IsNullOrWhiteSpace($friendlyName)) {
                continue
            }

            $skuId = $row.GUID
            if (-not [string]::IsNullOrWhiteSpace($skuId)) {
                $bySkuId[$skuId.Trim()] = $friendlyName
            }

            $skuPartNumber = $row.String_Id
            if (-not [string]::IsNullOrWhiteSpace($skuPartNumber)) {
                $bySkuPartNumber[$skuPartNumber.Trim()] = $friendlyName
            }
        }
    } catch {
        Write-Warning "License mapping parse failed from '$cachePath': $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        BySkuId = $bySkuId
        BySkuPartNumber = $bySkuPartNumber
    }
}

function Get-StorageContext {
    <#
    .SYNOPSIS
    Creates an authenticated Azure Storage context.
    Uses connection string when provided or managed identity/connected account for secure default auth.

    .EXAMPLE
    Get-StorageContext -Config (Get-StorageConfig -ExportName 'SUBSCRIPTIONS')
    #>
    param([PSCustomObject]$Config)
    if (-not [string]::IsNullOrWhiteSpace($Config.ConnectionString)) {
        return New-AzStorageContext -ConnectionString $Config.ConnectionString
    }

    if ([string]::IsNullOrWhiteSpace($Config.StorageAccount)) {
        throw "Storage account name is required when no connection string is provided."
    }

    if (-not [string]::IsNullOrWhiteSpace($env:WEBSITE_INSTANCE_ID)) {
        Connect-AzAccount -Identity | Out-Null
    }
    return New-AzStorageContext -StorageAccountName $Config.StorageAccount -UseConnectedAccount
}

function Test-StorageConnectivity {
    <#
    .SYNOPSIS
    Validates access to the configured storage container.
    Acts as a preflight check so export runs fail early with clear storage access errors.

    .EXAMPLE
    Test-StorageConnectivity -Config (Get-StorageConfig -ExportName 'SUBSCRIPTIONS') -Context $ctx
    #>
    param(
        [PSCustomObject]$Config,
        $Context
    )
    if ([string]::IsNullOrWhiteSpace($Config.StorageContainer)) {
        throw "Storage container is required for export."
    }

    $blobEndpoint = [string](Get-ObjectPropertyValue -InputObject $Context -Name 'BlobEndPoint')
    if ([string]::IsNullOrWhiteSpace($blobEndpoint)) {
        $blobEndpoint = [string](Get-ObjectPropertyValue -InputObject $Context -Name 'BlobEndpoint')
    }
    if ([string]::IsNullOrWhiteSpace($blobEndpoint) -and -not [string]::IsNullOrWhiteSpace($Config.StorageAccount)) {
        $blobEndpoint = "https://$($Config.StorageAccount).blob.core.windows.net"
    }

    if (-not [string]::IsNullOrWhiteSpace($blobEndpoint)) {
        try {
            $endpointUri = if ($blobEndpoint -match '^https?://') {
                [uri]$blobEndpoint
            } else {
                [uri]("https://$blobEndpoint")
            }
            $tcpClient = [System.Net.Sockets.TcpClient]::new()
            try {
                $connectTask = $tcpClient.ConnectAsync($endpointUri.Host, 443)
                if (-not $connectTask.Wait(3000)) {
                    throw "Timed out connecting to $($endpointUri.Host):443"
                }
            } finally {
                $tcpClient.Dispose()
            }
        } catch {
            Write-Error "Storage network precheck failed for '$blobEndpoint' on TCP 443: $($_.Exception.Message)"
            return $false
        }
    }

    try {
        Get-AzStorageContainer -Context $Context -Name $Config.StorageContainer -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Error "Storage connectivity test failed for container '$($Config.StorageContainer)': $($_.Exception.Message)"
        return $false
    }
}

function Get-ExportTitle {
    <#
    .SYNOPSIS
    Builds a display title for an export.
    Provides consistent human-readable titles for HTML export rendering.

    .EXAMPLE
    Get-ExportTitle -ExportName 'SUBSCRIPTIONS'
    #>
    param([string]$ExportName)
    if ([string]::IsNullOrWhiteSpace($ExportName)) {
        return "Export"
    }
    $knownTitles = @{
        'ENTRAROLEMEMBERS' = 'Entra Role Members'
        'GROUPMEMBERS' = 'Group Members'
        'AUGROUPMEMBERS' = 'Administrative Unit Group Members'
        'SUBSCRIPTIONS' = 'Subscriptions'
        'APPREGS' = 'App Registrations'
        'GRAPHPERMS' = 'Graph Permissions'
        'LICENSES' = 'Licenses'
        'INACTIVEENTRAADMINS' = 'Inactive Entra Admins'
    }
    $normalized = $ExportName.Trim().ToUpperInvariant()
    if ($knownTitles.ContainsKey($normalized)) {
        return $knownTitles[$normalized]
    }
    if ($normalized.StartsWith('ACCOUNTMATCH_', [System.StringComparison]::Ordinal)) {
        $suffix = $normalized.Substring('ACCOUNTMATCH_'.Length)
        if ([string]::IsNullOrWhiteSpace($suffix)) {
            return 'Account Match'
        }
        return "Account Match $suffix"
    }
    $title = $ExportName -replace '([a-z])([A-Z])', '$1 $2'
    if ($title.StartsWith("Export ", [System.StringComparison]::OrdinalIgnoreCase)) {
        $title = $title.Substring(7)
    }
    return $title.Trim()
}

function ConvertTo-StyledTableHtml {
    <#
    .SYNOPSIS
    Applies inline table styles to generated HTML.
    Ensures exported HTML exports have consistent readable table formatting.

    .EXAMPLE
    ConvertTo-StyledTableHtml -Html '<table><tr><th>A</th></tr><tr><td>1</td></tr></table>'
    #>
    param([string]$Html)
    $tableStyle = "width:100%;border-collapse:collapse;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;background-color:#ffffff;"
    $thStyle = "text-align:left;padding:8px 10px;background-color:#f3f4f6;border-bottom:1px solid #e5e7eb;font-size:12px;font-weight:600;color:#374151;"
    $tdStyle = "padding:8px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;color:#111827;vertical-align:top;"
    $htmlWithTable = [regex]::Replace($Html, "<table[^>]*>", "<table style=`"$tableStyle`">")
    $htmlWithTh = [regex]::Replace($htmlWithTable, "<th>", "<th style=`"$thStyle`">")
    return [regex]::Replace($htmlWithTh, "<td>", "<td style=`"$tdStyle`">")
}

function Convert-ExportToHtml {
    <#
    .SYNOPSIS
    Renders export rows to styled HTML output.
    Builds export HTML with metadata and table sections before style normalization.

    .EXAMPLE
    Convert-ExportToHtml -Data @([pscustomobject]@{ SubscriptionId='1'; SubscriptionName='Demo' }) -ExportName 'SUBSCRIPTIONS'
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Data,
        [Parameter(Mandatory)]
        [string]$ExportName
    )
    $title = Get-ExportTitle -ExportName $ExportName
    $generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    $bodyStyle = "margin:0;padding:0;background-color:#f8fafc;font-family:Segoe UI, Arial, sans-serif;color:#1f2937;"
    $containerStyle = "max-width:900px;margin:0 auto;padding:24px;"
    $headerStyle = "padding:16px 20px;background-color:#ffffff;border:1px solid #e5e7eb;border-radius:10px;margin-bottom:16px;"
    $titleStyle = "margin:0;font-size:20px;font-weight:600;color:#111827;"
    $subtitleStyle = "margin:4px 0 0 0;font-size:12px;color:#6b7280;"
    $sectionStyle = "margin-top:16px;"
    $sectionTitleStyle = "margin:16px 0 8px 0;font-size:16px;font-weight:600;color:#111827;"

    $sections = @()
    switch ($ExportName.ToLowerInvariant()) {
        "exportroles" {
            $groups = $Data | Group-Object -Property Role | Sort-Object Name
            foreach ($group in $groups) {
                $rows = $group.Group | Select-Object * -ExcludeProperty Role
                $tableHtml = ($rows | ConvertTo-Html -As Table -Fragment) -join "`n"
                $sections += "<div style=`"$sectionStyle`"><div style=`"$sectionTitleStyle`">$($group.Name)</div>$tableHtml</div>"
            }
        }
        default {
            $tableHtml = ($Data | ConvertTo-Html -As Table -Fragment) -join "`n"
            $sections += "<div style=`"$sectionStyle`">$tableHtml</div>"
        }
    }

    $content = $sections -join "`n"
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>$title</title>
</head>
<body style="$bodyStyle">
    <div style="$containerStyle">
        <div style="$headerStyle">
            <h1 style="$titleStyle">$title</h1>
            <div style="$subtitleStyle">Generated $generatedAt</div>
        </div>
        $content
    </div>
</body>
</html>
"@

    return ConvertTo-StyledTableHtml -Html $html
}

function Write-ExportFormatToStorage {
    <#
    .SYNOPSIS
    Serializes one format and uploads it to blob storage.
    Encapsulates per-format conversion, timestamped file naming, and blob upload.

    .EXAMPLE
    Write-ExportFormatToStorage -Context $ctx -ContainerName 'exports' -BlobPrefix 'subscriptions' -FileNameBase 'subscriptions' -Format 'json' -Data $rows -ExportName 'SUBSCRIPTIONS'
    #>
    param(
        [Parameter(Mandatory)]
        $Context,
        [Parameter(Mandatory)]
        [string]$ContainerName,
        [Parameter(Mandatory)]
        [string]$BlobPrefix,
        [Parameter(Mandatory)]
        [string]$FileNameBase,
        [Parameter(Mandatory)]
        [string]$Format,
        [Parameter(Mandatory)]
        [object[]]$Data,
        [Parameter(Mandatory)]
        [string]$ExportName
    )

    $content = $null
    switch ($Format) {
        "json" { $content = ($Data | ConvertTo-Json -Depth 6) }
        "csv" { $content = ($Data | ConvertTo-Csv -NoTypeInformation) -join "`n" }
        "html" { $content = Convert-ExportToHtml -Data $Data -ExportName $ExportName }
        default { throw "Unsupported export format '$Format'." }
    }

    $tempName = [System.IO.Path]::GetRandomFileName()
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$tempName.$Format")
    try {
        $content | Set-Content -Path $tempFile -Encoding UTF8
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $fileName = "{0}_{1}.{2}" -f $FileNameBase, $timestamp, $Format
        if ([string]::IsNullOrWhiteSpace($BlobPrefix)) {
            $blobName = $fileName
        } else {
            $blobName = ($BlobPrefix.TrimEnd("/") + "/" + $fileName)
        }
        Set-AzStorageBlobContent -Context $Context -Container $ContainerName -File $tempFile -Blob $blobName -Force | Out-Null
        Write-Host "Uploaded $Format export to $ContainerName/$blobName"
        Write-ExportRuntimeLog -ExportName $ExportName -Stage 'write' -Event 'blob_uploaded' -Status 'ok' -Data @{
            format = $Format
            container = $ContainerName
            blob = $blobName
        }
        return $blobName
    } finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-ExportToStorage {
    <#
    .SYNOPSIS
    Writes all configured export formats to storage.
    Orchestrates storage context, connectivity checks, and multi-format write operations.

    .EXAMPLE
    Write-ExportToStorage -ExportName 'SUBSCRIPTIONS' -Data $rows
    #>
    param(
        [string]$ExportName,
        [object[]]$Data,
        [string]$BlobPrefix,
        [string]$FileNameBase
    )
    $config = Get-StorageConfig -ExportName $ExportName
    $ctx = Get-StorageContext -Config $config

    if (-not (Test-StorageConnectivity -Config $config -Context $ctx)) {
        throw "Storage connectivity test failed."
    }

    $formats = Get-ExportFormats -ExportName $ExportName
    $effectiveBlobPrefix = $BlobPrefix
    if ([string]::IsNullOrWhiteSpace($effectiveBlobPrefix)) {
        $effectiveBlobPrefix = $config.BlobPrefix
    }
    $effectiveFileNameBase = $FileNameBase
    if ([string]::IsNullOrWhiteSpace($effectiveFileNameBase)) {
        $effectiveFileNameBase = $ExportName.ToLowerInvariant()
    }

    Write-ExportRuntimeLog -ExportName $ExportName -Stage 'write' -Event 'storage_selected' -Status 'ok' -Data @{
        storageAccount = $config.StorageAccount
        container = $config.StorageContainer
        blobPrefix = $effectiveBlobPrefix
        fileBase = $effectiveFileNameBase
        formats = (@($formats) -join ',')
    }

    $blobsWritten = 0
    foreach ($format in $formats) {
        $writeExportFormatParams = @{
            Context = $ctx
            ContainerName = $config.StorageContainer
            BlobPrefix = $effectiveBlobPrefix
            FileNameBase = $effectiveFileNameBase
            Format = $format
            Data = $Data
            ExportName = $ExportName
        }
        $blobName = Write-ExportFormatToStorage @writeExportFormatParams
        if (-not [string]::IsNullOrWhiteSpace($blobName)) {
            $blobsWritten++
        }
    }
    return $blobsWritten
}

function Resolve-PrincipalInfo {
    <#
    .SYNOPSIS
    Resolves principal type and display name with caching.
    Avoids repeated Graph lookups and normalizes principal metadata for role exports.

    .EXAMPLE
    Resolve-PrincipalInfo -PrincipalId '00000000-0000-0000-0000-000000000000' -Cache @{}
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PrincipalId,
        [hashtable]$Cache
    )
    if ($Cache.ContainsKey($PrincipalId)) {
        return $Cache[$PrincipalId]
    }

    try {
        $obj = Get-MgDirectoryObject -DirectoryObjectId $PrincipalId -Property "id,displayName" -ErrorAction Stop
        $friendlyType = "Unknown"
        $type = $null
        if ($obj.PSObject.Properties.Name -contains "OdataType") {
            $type = $obj.OdataType
        }
        if ([string]::IsNullOrWhiteSpace($type)) {
            $type = $obj.AdditionalProperties["@odata.type"]
        }
        switch ($type) {
            "#microsoft.graph.user" { $friendlyType = "User" }
            "#microsoft.graph.group" { $friendlyType = "Group" }
            "#microsoft.graph.servicePrincipal" { $friendlyType = "ServicePrincipal" }
            "#microsoft.graph.application" { $friendlyType = "Application" }
            default {
                if (-not [string]::IsNullOrWhiteSpace($type)) {
                    $friendlyType = $type.TrimStart("#microsoft.graph.")
                }
            }
        }
        $displayName = $obj.AdditionalProperties["displayName"]

        $result = [PSCustomObject]@{
            PrincipalType = $friendlyType
            DisplayName   = $displayName
        }
    } catch {
        Write-Warning ("Resolve-PrincipalInfo failed for principalId='{0}': {1}" -f $PrincipalId, $_.Exception.Message)
        $result = [PSCustomObject]@{
            PrincipalType = "unknown"
            DisplayName   = $null
        }
    }

    $Cache[$PrincipalId] = $result
    return $result
}

function Get-RoleAssignmentsExport {
    <#
    .SYNOPSIS
    Builds the Entra role assignments export dataset.
    Collects active and eligible role assignments and enriches them with resolved principal details.

    .EXAMPLE
    Get-RoleAssignmentsExport
    #>
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null

    $roleDefinitions = @(
        Get-MgRoleManagementDirectoryRoleDefinition -All -Property 'id,displayName' -ErrorAction Stop
    )
    $roleMap = @{}
    foreach ($role in $roleDefinitions) {
        $roleMap[$role.Id] = $role.DisplayName
    }

    $principalCache = @{}
    $rows = @()
    $toDateOnlyString = {
        param($Value)
        $utcDate = ConvertTo-NullableUtcDateTime -Value $Value
        if ($null -eq $utcDate) { return $null }
        return $utcDate.ToString('yyyy-MM-dd')
    }

    $activeAssignments = @(
        Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -All -Property 'principalId,roleDefinitionId,startDateTime,endDateTime' -ErrorAction Stop
    )
    foreach ($assignment in $activeAssignments) {
        $principal = Resolve-PrincipalInfo -PrincipalId $assignment.PrincipalId -Cache $principalCache
        $rows += [PSCustomObject]@{
            #RoleId              = $assignment.RoleDefinitionId
            Role     = $roleMap[$assignment.RoleDefinitionId]
            AssignmentType      = "Active"
            PrincipalId         = $assignment.PrincipalId
            PrincipalType       = $principal.PrincipalType
            PrincipalDisplayName= $principal.DisplayName
            StartDateTime       = & $toDateOnlyString $assignment.StartDateTime
            EndDateTime         = & $toDateOnlyString $assignment.EndDateTime
        }
    }

    $eligibleAssignments = @(
        Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -All -Property 'principalId,roleDefinitionId,startDateTime,endDateTime' -ErrorAction Stop
    )
    foreach ($assignment in $eligibleAssignments) {
        $principal = Resolve-PrincipalInfo -PrincipalId $assignment.PrincipalId -Cache $principalCache
        $rows += [PSCustomObject]@{
            #RoleId              = $assignment.RoleDefinitionId
            Role     = $roleMap[$assignment.RoleDefinitionId]
            AssignmentType      = "Eligible"
            PrincipalId         = $assignment.PrincipalId
            PrincipalType       = $principal.PrincipalType
            PrincipalDisplayName= $principal.DisplayName
            StartDateTime       = & $toDateOnlyString $assignment.StartDateTime
            EndDateTime         = & $toDateOnlyString $assignment.EndDateTime
        }
    }

    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        roleDefinitions = @($roleDefinitions).Count
        activeAssignments = @($activeAssignments).Count
        eligibleAssignments = @($eligibleAssignments).Count
        rows = @($rows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $rows
}

function Resolve-GroupMemberExportGroupIds {
    <#
    .SYNOPSIS
    Resolves and validates target group IDs for group member exports.
    Allows explicit input or config-driven group IDs while enforcing at least one valid value.

    .EXAMPLE
    Resolve-GroupMemberExportGroupIds -GroupId @('11111111-1111-1111-1111-111111111111')
    #>
    param(
        [AllowNull()]
        [object]$GroupId
    )
    $groupIdValue = $GroupId
    if (-not (Test-HasUsableValue -Value $groupIdValue)) {
        $groupIdValue = Get-ExportSetting -ExportName 'GROUPMEMBERS' -Name 'groupIds'
        if (-not (Test-HasUsableValue -Value $groupIdValue)) {
            $groupIdValue = Get-ExportSetting -ExportName 'GROUPMEMBERS' -Name 'groupId' -Required
        }
    }

    $groupIds = @(ConvertTo-NormalizedStringList -InputValues @($groupIdValue) -SplitCsv)
    if ($groupIds.Count -eq 0) {
        throw "GROUPMEMBERS requires at least one groupIds value in exports.config.json exports.GROUPMEMBERS.groupIds."
    }

    return $groupIds
}

function Resolve-GroupMemberProperties {
    <#
    .SYNOPSIS
    Resolves selected output properties for group member export.
    Combines shared and per-group exclusions so output columns match export intent.

    .EXAMPLE
    Resolve-GroupMemberProperties -GroupId '11111111-1111-1111-1111-111111111111'
    #>
    param(
        [Parameter(Mandatory)]
        [string]$GroupId
    )
    $basePropertiesValue = Get-ExportSetting -ExportName 'GROUPMEMBERS' -Name 'properties' -Default @()
    $excludeByGroupValue = Get-ExportSetting -ExportName 'GROUPMEMBERS' -Name 'excludePropertiesByGroup' -Default @{}

    $baseProperties = @(ConvertTo-NormalizedStringList -InputValues @($basePropertiesValue) -SplitCsv)

    $excludedProperties = @()
    if ($excludeByGroupValue -is [hashtable] -and $excludeByGroupValue.ContainsKey($GroupId)) {
        $excludedValue = $excludeByGroupValue[$GroupId]
        $excludedProperties = @(ConvertTo-NormalizedStringList -InputValues @($excludedValue) -SplitCsv)
    }

    $effectiveProperties = @($baseProperties)
    if ($excludedProperties.Count -gt 0) {
        $excludedLookup = @{}
        foreach ($name in $excludedProperties) {
            $excludedLookup[$name.ToLowerInvariant()] = $true
        }
        $effectiveProperties = @(
            $baseProperties |
                Where-Object { -not $excludedLookup.ContainsKey($_.ToLowerInvariant()) }
        )
    }

    # Always include user identity in GROUPMEMBERS exports.
    if (-not (@($effectiveProperties | Where-Object { $_.ToLowerInvariant() -eq 'userid' }).Count -gt 0)) {
        $effectiveProperties = @('UserId') + $effectiveProperties
    }

    return $effectiveProperties
}

function Get-GroupMemberPropertyPlan {
    <#
    .SYNOPSIS
    Builds select and output mappings for group member properties.
    Translates requested property names into Graph select fields and output column mapping rules.

    .EXAMPLE
    Get-GroupMemberPropertyPlan -Properties @('mail','extensionAttribute2')
    #>
    param(
        [AllowNull()]
        [object[]]$Properties,
        [switch]$IncludeAdministrativeUnitContext
    )

    $selectProperties = @()
    $outputMappings = @()

    foreach ($rawPropertyName in @($Properties)) {
        $propertyName = [string]$rawPropertyName
        if ([string]::IsNullOrWhiteSpace($propertyName)) {
            continue
        }
        $propertyName = $propertyName.Trim()
        $normalizedPropertyName = $propertyName.ToLowerInvariant()

        if ($normalizedPropertyName -eq 'groupid') {
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'GroupId'
                SourceScope    = 'context'
                SourceProperty = 'GroupId'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'groupdisplayname') {
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'GroupDisplayName'
                SourceScope    = 'context'
                SourceProperty = 'GroupDisplayName'
                NestedProperty = $null
            }
            continue
        }
        if ($IncludeAdministrativeUnitContext -and $normalizedPropertyName -eq 'administrativeunitid') {
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'AdministrativeUnitId'
                SourceScope    = 'context'
                SourceProperty = 'AdministrativeUnitId'
                NestedProperty = $null
            }
            continue
        }
        if ($IncludeAdministrativeUnitContext -and $normalizedPropertyName -eq 'administrativeunitdisplayname') {
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'AdministrativeUnitDisplayName'
                SourceScope    = 'context'
                SourceProperty = 'AdministrativeUnitDisplayName'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'userid') {
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'UserId'
                SourceScope    = 'member'
                SourceProperty = 'id'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'userprincipalname') {
            $selectProperties += 'userPrincipalName'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'UserPrincipalName'
                SourceScope    = 'member'
                SourceProperty = 'userPrincipalName'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'displayname') {
            $selectProperties += 'displayName'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'DisplayName'
                SourceScope    = 'member'
                SourceProperty = 'displayName'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'usertype') {
            $selectProperties += 'userType'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'UserType'
                SourceScope    = 'member'
                SourceProperty = 'userType'
                NestedProperty = $null
            }
            continue
        }

        if ($normalizedPropertyName -match '^extensionattribute([1-9]|1[0-5])$') {
            $attributeName = "extensionAttribute$($Matches[1])"
            $selectProperties += 'onPremisesExtensionAttributes'
            $outputMappings += [PSCustomObject]@{
                OutputName     = $propertyName
                SourceScope    = 'member'
                SourceProperty = 'onPremisesExtensionAttributes'
                NestedProperty = $attributeName
            }
            continue
        }

        if ($normalizedPropertyName -match '^onpremisesextensionattributes\.(extensionattribute([1-9]|1[0-5]))$') {
            $attributeName = "extensionAttribute$($Matches[2])"
            $selectProperties += 'onPremisesExtensionAttributes'
            $outputMappings += [PSCustomObject]@{
                OutputName     = $propertyName
                SourceScope    = 'member'
                SourceProperty = 'onPremisesExtensionAttributes'
                NestedProperty = $attributeName
            }
            continue
        }

        $selectProperties += $propertyName
        $outputMappings += [PSCustomObject]@{
            OutputName     = $propertyName
            SourceScope    = 'member'
            SourceProperty = $propertyName
            NestedProperty = $null
        }
    }

    return [PSCustomObject]@{
        SelectProperties = @($selectProperties | Select-Object -Unique)
        OutputMappings   = @($outputMappings)
    }
}

function Get-InvalidSelectPropertyNameFromError {
    <#
    .SYNOPSIS
    Attempts to extract an invalid select property name from Microsoft Graph error text.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $messages = @()
    if ($ErrorRecord.Exception) {
        $messages += [string]$ErrorRecord.Exception.Message
    }
    if ($ErrorRecord.ErrorDetails) {
        $messages += [string]$ErrorRecord.ErrorDetails.Message
    }

    foreach ($message in @($messages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($message -match "property named '([^']+)'") { return [string]$Matches[1] }
        if ($message -match "property '([^']+)'") { return [string]$Matches[1] }
        if ($message -match "\$select[^']*'([^']+)'") { return [string]$Matches[1] }
    }

    return $null
}

function Get-GroupMembersExport {
    <#
    .SYNOPSIS
    Builds the group members export dataset.
    Queries transitive user membership per target group and shapes rows with configured properties.

    .EXAMPLE
    Get-GroupMembersExport -GroupId '11111111-1111-1111-1111-111111111111'
    #>
    param(
        [AllowNull()]
        [object]$GroupId
    )
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null
    $groupIds = Resolve-GroupMemberExportGroupIds -GroupId $GroupId
    Write-ExportRuntimeLog -Stage 'collect' -Event 'scope_resolved' -Status 'ok' -Data @{
        targetGroups = @($groupIds).Count
    }

    $rows = @()
    $groupsWithZeroMembers = 0
    $totalMembers = 0
    $groupsSkippedNoValidProperties = 0
    foreach ($resolvedGroupId in $groupIds) {
        $groupDisplayName = $null
        try {
            $groupParams = @{
                GroupId = $resolvedGroupId
                Property = 'id,displayName'
                ErrorAction = 'Stop'
            }
            $group = Get-MgGroup @groupParams
            $groupDisplayName = [string](Get-ObjectPropertyValue -InputObject $group -Name 'displayName')
        } catch {
            throw "Failed loading GROUPMEMBERS group metadata for group '$resolvedGroupId': $($_.Exception.Message)"
        }

        $requestedProperties = @(Resolve-GroupMemberProperties -GroupId $resolvedGroupId)
        if (@($requestedProperties).Count -eq 0) {
            $groupsSkippedNoValidProperties++
            Write-Warning "GROUPMEMBERS export has no configured properties for group '$resolvedGroupId'. Set exports.GROUPMEMBERS.properties."
            Write-ExportRuntimeLog -Stage 'collect' -Event 'group_skipped_no_properties' -Status 'warn' -Data @{
                groupId = $resolvedGroupId
            }
            continue
        }

        $members = @()
        $propertyPlan = $null
        $remainingProperties = @($requestedProperties)
        while ($true) {
            $propertyPlan = Get-GroupMemberPropertyPlan -Properties $remainingProperties
            if (@($propertyPlan.OutputMappings).Count -eq 0) {
                $groupsSkippedNoValidProperties++
                Write-Warning "GROUPMEMBERS export has no valid properties after filtering for group '$resolvedGroupId'."
                Write-ExportRuntimeLog -Stage 'collect' -Event 'group_skipped_no_valid_properties' -Status 'warn' -Data @{
                    groupId = $resolvedGroupId
                }
                break
            }

            $selectProperties = @('id') + $propertyPlan.SelectProperties | Select-Object -Unique
            $selectQuery = [string]::Join(',', $selectProperties)
            try {
                $groupMemberParams = @{
                    GroupId = $resolvedGroupId
                    All = $true
                    Property = $selectQuery
                    ErrorAction = 'Stop'
                }
                $members = @(Get-MgGroupTransitiveMemberAsUser @groupMemberParams)
                break
            } catch {
                $invalidProperty = Get-InvalidSelectPropertyNameFromError -ErrorRecord $_
                if ([string]::IsNullOrWhiteSpace($invalidProperty)) {
                    throw "Failed loading GROUPMEMBERS users for group '$resolvedGroupId' with select '$selectQuery': $($_.Exception.Message)"
                }

                $invalidLookup = $invalidProperty.Trim().ToLowerInvariant()
                $filteredProperties = @($remainingProperties | Where-Object { $_.ToLowerInvariant() -ne $invalidLookup })
                if (@($filteredProperties).Count -eq @($remainingProperties).Count) {
                    throw "Failed loading GROUPMEMBERS users for group '$resolvedGroupId' with select '$selectQuery': $($_.Exception.Message)"
                }

                Write-Warning "GROUPMEMBERS property '$invalidProperty' is invalid and will be skipped for group '$resolvedGroupId'."
                Write-ExportRuntimeLog -Stage 'collect' -Event 'property_removed_invalid' -Status 'warn' -Data @{
                    groupId = $resolvedGroupId
                    property = $invalidProperty
                }
                $remainingProperties = $filteredProperties
            }
        }
        if ($null -eq $propertyPlan -or @($propertyPlan.OutputMappings).Count -eq 0) {
            continue
        }

        $memberCount = @($members).Count
        $totalMembers += $memberCount
        if ($memberCount -eq 0) {
            $groupsWithZeroMembers++
        }
        foreach ($member in $members) {
            $row = [ordered]@{
                __PartitionGroupId = $resolvedGroupId
            }
            foreach ($propertyMapping in $propertyPlan.OutputMappings) {
                $value = $null
                if ($propertyMapping.SourceScope -eq 'context') {
                    switch ([string]$propertyMapping.SourceProperty) {
                        'GroupId' { $value = $resolvedGroupId }
                        'GroupDisplayName' { $value = $groupDisplayName }
                        default { $value = $null }
                    }
                } else {
                    if (Test-HasUsableValue -Value $propertyMapping.NestedProperty) {
                        $parentObject = Get-ObjectPropertyValue -InputObject $member -Name $propertyMapping.SourceProperty
                        $value = Get-ObjectPropertyValue -InputObject $parentObject -Name $propertyMapping.NestedProperty
                    } else {
                        $value = Get-ObjectPropertyValue -InputObject $member -Name $propertyMapping.SourceProperty
                    }
                }
                $row[[string]$propertyMapping.OutputName] = $value
            }
            $rows += [PSCustomObject]$row
        }
    }

    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        targetGroups = @($groupIds).Count
        groupsWithZeroMembers = $groupsWithZeroMembers
        groupsSkippedNoValidProperties = $groupsSkippedNoValidProperties
        members = $totalMembers
        rows = @($rows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $rows
}

function Resolve-AuGroupMemberExportAdministrativeUnitIds {
    <#
    .SYNOPSIS
    Resolves and validates target administrative unit IDs for AU group member exports.
    Allows explicit input or config-driven administrative unit IDs while enforcing at least one valid value.

    .EXAMPLE
    Resolve-AuGroupMemberExportAdministrativeUnitIds -AdministrativeUnitId @('11111111-1111-1111-1111-111111111111')
    #>
    param(
        [AllowNull()]
        [object]$AdministrativeUnitId
    )
    $administrativeUnitIdValue = $AdministrativeUnitId
    if (-not (Test-HasUsableValue -Value $administrativeUnitIdValue)) {
        $administrativeUnitIdValue = Get-ExportSetting -ExportName 'AUGROUPMEMBERS' -Name 'administrativeUnitIds'
        if (-not (Test-HasUsableValue -Value $administrativeUnitIdValue)) {
            $administrativeUnitIdValue = Get-ExportSetting -ExportName 'AUGROUPMEMBERS' -Name 'administrativeUnitId' -Required
        }
    }

    $administrativeUnitIds = @(ConvertTo-NormalizedStringList -InputValues @($administrativeUnitIdValue) -SplitCsv)
    if ($administrativeUnitIds.Count -eq 0) {
        throw "AUGROUPMEMBERS requires at least one administrativeUnitIds value in exports.config.json exports.AUGROUPMEMBERS.administrativeUnitIds."
    }

    return $administrativeUnitIds
}

function Resolve-AuGroupMemberProperties {
    <#
    .SYNOPSIS
    Resolves selected output properties for AU group member export.
    Applies configured properties and enforces required AU/group/user identity columns.

    .EXAMPLE
    Resolve-AuGroupMemberProperties
    #>
    param()
    $basePropertiesValue = Get-ExportSetting -ExportName 'AUGROUPMEMBERS' -Name 'properties' -Default @()

    $baseProperties = @(ConvertTo-NormalizedStringList -InputValues @($basePropertiesValue) -SplitCsv)
    $effectiveProperties = @($baseProperties)

    # Always include AU/group/user identity in AUGROUPMEMBERS exports.
    $requiredProperties = @('AdministrativeUnitId', 'GroupId', 'GroupDisplayName', 'UserId')
    for ($i = $requiredProperties.Count - 1; $i -ge 0; $i--) {
        $requiredProperty = $requiredProperties[$i]
        if (-not (@($effectiveProperties | Where-Object { $_.ToLowerInvariant() -eq $requiredProperty.ToLowerInvariant() }).Count -gt 0)) {
            $effectiveProperties = @($requiredProperty) + $effectiveProperties
        }
    }

    return $effectiveProperties
}

function Get-AuGroupMemberGroupTargets {
    <#
    .SYNOPSIS
    Resolves AU and group metadata for the AU group members export.
    Enumerates groups contained by each configured administrative unit for downstream member expansion.

    .EXAMPLE
    Get-AuGroupMemberGroupTargets -AdministrativeUnitId '11111111-1111-1111-1111-111111111111'
    #>
    param(
        [AllowNull()]
        [object]$AdministrativeUnitId
    )
    $administrativeUnitIds = Resolve-AuGroupMemberExportAdministrativeUnitIds -AdministrativeUnitId $AdministrativeUnitId
    Write-ExportRuntimeLog -Stage 'collect' -Event 'scope_resolved' -Status 'ok' -Data @{
        administrativeUnits = @($administrativeUnitIds).Count
    }
    $targets = @()

    foreach ($resolvedAdministrativeUnitId in $administrativeUnitIds) {
        $administrativeUnit = $null
        try {
            $administrativeUnitParams = @{
                AdministrativeUnitId = $resolvedAdministrativeUnitId
                Property = 'id,displayName'
                ErrorAction = 'Stop'
            }
            $administrativeUnit = Get-MgDirectoryAdministrativeUnit @administrativeUnitParams
        } catch {
            throw "Failed loading AUGROUPMEMBERS administrative unit '$resolvedAdministrativeUnitId': $($_.Exception.Message)"
        }

        $administrativeUnitDisplayName = [string](Get-ObjectPropertyValue -InputObject $administrativeUnit -Name 'displayName')
        $groups = @()
        try {
            $auGroupParams = @{
                AdministrativeUnitId = $resolvedAdministrativeUnitId
                All = $true
                Property = 'id,displayName'
                ErrorAction = 'Stop'
            }
            $groups = @(Get-MgDirectoryAdministrativeUnitMemberAsGroup @auGroupParams)
        } catch {
            throw "Failed loading AUGROUPMEMBERS groups for administrative unit '$resolvedAdministrativeUnitId': $($_.Exception.Message)"
        }

        foreach ($group in $groups) {
            $groupId = [string](Get-ObjectPropertyValue -InputObject $group -Name 'id')
            if ([string]::IsNullOrWhiteSpace($groupId)) {
                continue
            }

            $targets += [PSCustomObject]@{
                AdministrativeUnitId          = $resolvedAdministrativeUnitId
                AdministrativeUnitDisplayName = $administrativeUnitDisplayName
                GroupId                       = $groupId
                GroupDisplayName              = [string](Get-ObjectPropertyValue -InputObject $group -Name 'displayName')
            }
        }
    }

    Write-ExportRuntimeLog -Stage 'collect' -Event 'au_groups_resolved' -Status 'ok' -Data @{
        administrativeUnits = @($administrativeUnitIds).Count
        groups = @($targets).Count
    }
    return $targets
}

function Get-AuGroupMembersExport {
    <#
    .SYNOPSIS
    Builds the administrative unit group members export dataset.
    Enumerates groups in configured administrative units, expands transitive user members, and flags guest users.

    .EXAMPLE
    Get-AuGroupMembersExport -AdministrativeUnitId '11111111-1111-1111-1111-111111111111'
    #>
    param(
        [AllowNull()]
        [object]$AdministrativeUnitId
    )
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null
    $targets = Get-AuGroupMemberGroupTargets -AdministrativeUnitId $AdministrativeUnitId

    $rows = @()
    $groupsWithZeroMembers = 0
    $totalMembers = 0
    $groupsSkippedNoValidProperties = 0
    foreach ($target in $targets) {
        $groupId = [string]$target.GroupId
        if ([string]::IsNullOrWhiteSpace($groupId)) {
            continue
        }

        $requestedProperties = @(Resolve-AuGroupMemberProperties)
        if (@($requestedProperties).Count -eq 0) {
            $groupsSkippedNoValidProperties++
            Write-Warning "AUGROUPMEMBERS export has no configured properties for group '$groupId'. Set exports.AUGROUPMEMBERS.properties."
            Write-ExportRuntimeLog -Stage 'collect' -Event 'group_skipped_no_properties' -Status 'warn' -Data @{
                administrativeUnitId = [string]$target.AdministrativeUnitId
                groupId = $groupId
            }
            continue
        }

        $members = @()
        $propertyPlan = $null
        $remainingProperties = @($requestedProperties)
        while ($true) {
            $propertyPlan = Get-GroupMemberPropertyPlan -Properties $remainingProperties -IncludeAdministrativeUnitContext
            if (@($propertyPlan.OutputMappings).Count -eq 0) {
                $groupsSkippedNoValidProperties++
                Write-Warning "AUGROUPMEMBERS export has no valid properties after filtering for group '$groupId'."
                Write-ExportRuntimeLog -Stage 'collect' -Event 'group_skipped_no_valid_properties' -Status 'warn' -Data @{
                    administrativeUnitId = [string]$target.AdministrativeUnitId
                    groupId = $groupId
                }
                break
            }

            $selectProperties = @('id') + $propertyPlan.SelectProperties | Select-Object -Unique
            $selectQuery = [string]::Join(',', $selectProperties)
            try {
                $auGroupMemberParams = @{
                    GroupId = $groupId
                    All = $true
                    Property = $selectQuery
                    ErrorAction = 'Stop'
                }
                $members = @(Get-MgGroupTransitiveMemberAsUser @auGroupMemberParams)
                break
            } catch {
                $invalidProperty = Get-InvalidSelectPropertyNameFromError -ErrorRecord $_
                if ([string]::IsNullOrWhiteSpace($invalidProperty)) {
                    throw "Failed loading AUGROUPMEMBERS users for administrative unit '$($target.AdministrativeUnitId)' and group '$groupId' with select '$selectQuery': $($_.Exception.Message)"
                }

                $invalidLookup = $invalidProperty.Trim().ToLowerInvariant()
                $filteredProperties = @($remainingProperties | Where-Object { $_.ToLowerInvariant() -ne $invalidLookup })
                if (@($filteredProperties).Count -eq @($remainingProperties).Count) {
                    throw "Failed loading AUGROUPMEMBERS users for administrative unit '$($target.AdministrativeUnitId)' and group '$groupId' with select '$selectQuery': $($_.Exception.Message)"
                }

                Write-Warning "AUGROUPMEMBERS property '$invalidProperty' is invalid and will be skipped for group '$groupId'."
                Write-ExportRuntimeLog -Stage 'collect' -Event 'property_removed_invalid' -Status 'warn' -Data @{
                    administrativeUnitId = [string]$target.AdministrativeUnitId
                    groupId = $groupId
                    property = $invalidProperty
                }
                $remainingProperties = $filteredProperties
            }
        }
        if ($null -eq $propertyPlan -or @($propertyPlan.OutputMappings).Count -eq 0) {
            continue
        }

        $memberCount = @($members).Count
        $totalMembers += $memberCount
        if ($memberCount -eq 0) {
            $groupsWithZeroMembers++
        }

        foreach ($member in $members) {
            $row = [ordered]@{
                __PartitionAdministrativeUnitId = [string]$target.AdministrativeUnitId
            }
            foreach ($propertyMapping in $propertyPlan.OutputMappings) {
                $value = $null
                if ($propertyMapping.SourceScope -eq 'context') {
                    switch ([string]$propertyMapping.SourceProperty) {
                        'AdministrativeUnitId' { $value = [string]$target.AdministrativeUnitId }
                        'AdministrativeUnitDisplayName' { $value = [string]$target.AdministrativeUnitDisplayName }
                        'GroupId' { $value = $groupId }
                        'GroupDisplayName' { $value = [string]$target.GroupDisplayName }
                        default { $value = $null }
                    }
                } else {
                    if (Test-HasUsableValue -Value $propertyMapping.NestedProperty) {
                        $parentObject = Get-ObjectPropertyValue -InputObject $member -Name $propertyMapping.SourceProperty
                        $value = Get-ObjectPropertyValue -InputObject $parentObject -Name $propertyMapping.NestedProperty
                    } else {
                        $value = Get-ObjectPropertyValue -InputObject $member -Name $propertyMapping.SourceProperty
                    }
                }
                $row[[string]$propertyMapping.OutputName] = $value
            }
            $rows += [PSCustomObject]$row
        }
    }

    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        groups = @($targets).Count
        groupsWithZeroMembers = $groupsWithZeroMembers
        groupsSkippedNoValidProperties = $groupsSkippedNoValidProperties
        members = $totalMembers
        rows = @($rows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $rows
}

function Get-SubscriptionsExport {
    <#
    .SYNOPSIS
    Builds the Azure subscriptions inventory export dataset.
    Queries Resource Graph at tenant scope and normalizes policy, management group, and dynamic tag columns.

    .EXAMPLE
    Get-SubscriptionsExport
    #>
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null

    $query = @'
resourcecontainers
| where type == 'microsoft.resources/subscriptions'
'@

    Write-Host "[SubscriptionsExport] Querying Azure Resource Graph at tenant scope."
    $results = Search-AzGraph -Query $query -UseTenantScope -First 1000 -ErrorAction Stop

    $toTagMap = {
        param([AllowNull()][object]$Tags)
        $map = @{}
        if ($null -eq $Tags) {
            return $map
        }

        if ($Tags -is [hashtable]) {
            foreach ($key in $Tags.Keys) {
                $map[[string]$key] = $Tags[$key]
            }
            return $map
        }

        if ($Tags -is [System.Collections.IDictionary]) {
            foreach ($key in $Tags.Keys) {
                $map[[string]$key] = $Tags[$key]
            }
            return $map
        }

        foreach ($prop in $Tags.PSObject.Properties) {
            if (-not [string]::IsNullOrWhiteSpace($prop.Name)) {
                $map[[string]$prop.Name] = $prop.Value
            }
        }
        return $map
    }

    $rows = @()
    foreach ($item in @($results)) {
        $properties = Get-ObjectPropertyValue -InputObject $item -Name 'properties'
        $tags = & $toTagMap (Get-ObjectPropertyValue -InputObject $item -Name 'tags')
        $subscriptionPolicies = Get-ObjectPropertyValue -InputObject $properties -Name 'subscriptionPolicies'
        $mgChain = @(Get-ObjectPropertyValue -InputObject $properties -Name 'managementGroupAncestorsChain')
        $assignedManagementGroup = $null
        if (@($mgChain).Count -gt 0) {
            $firstMg = $mgChain[0]
            $assignedManagementGroup = [string](Get-ObjectPropertyValue -InputObject $firstMg -Name 'displayName')
            if ([string]::IsNullOrWhiteSpace($assignedManagementGroup)) {
                $assignedManagementGroup = [string](Get-ObjectPropertyValue -InputObject $firstMg -Name 'name')
            }
        }

        $row = [ordered]@{
            SubscriptionId                    = [string](Get-ObjectPropertyValue -InputObject $item -Name 'subscriptionId')
            SubscriptionName                  = [string](Get-ObjectPropertyValue -InputObject $item -Name 'name')
            TenantId                          = [string](Get-ObjectPropertyValue -InputObject $item -Name 'tenantId')
            State                             = [string](Get-ObjectPropertyValue -InputObject $properties -Name 'state')
            QuotaId                           = [string](Get-ObjectPropertyValue -InputObject $subscriptionPolicies -Name 'quotaId')
            SpendingLimit                     = [string](Get-ObjectPropertyValue -InputObject $subscriptionPolicies -Name 'spendingLimit')
            LocationPlacementId               = [string](Get-ObjectPropertyValue -InputObject $subscriptionPolicies -Name 'locationPlacementId')
            ManagementGroup                   = $assignedManagementGroup
        }

        foreach ($tagKey in @($tags.Keys | Sort-Object)) {
            $columnName = 'Tag' + $tagKey
            $row[$columnName] = $tags[$tagKey]
        }

        $rows += [PSCustomObject]$row
    }

    Write-Host "[SubscriptionsExport] Retrieved $($rows.Count) subscriptions."
    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        queryRows = @($results).Count
        rows = @($rows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $rows
}

function Get-AppRegistrationsExport {
    <#
    .SYNOPSIS
    Builds the app registrations credential expiry export dataset.
    Extracts secret/certificate expiry details and computes status windows for alerting/exports.

    .EXAMPLE
    Get-AppRegistrationsExport
    #>
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null

    $thresholdDays = Get-ExportIntSetting -ExportName 'APPREGS' -Name 'expiryDays' -Default 30 -MinValue 0

    $apps = Get-MgApplication -All -Property "id,appId,displayName,passwordCredentials,keyCredentials"
    $rows = @()
    $getExpiryStatus = {
        param([datetime]$EndDateTime)
        $now = Get-Date
        $daysToExpiry = [math]::Floor(($EndDateTime.ToUniversalTime() - $now.ToUniversalTime()).TotalDays)
        if ($daysToExpiry -lt 0) {
            return [PSCustomObject]@{ Status = "Expired"; DaysToExpiry = $daysToExpiry }
        }
        if ($daysToExpiry -le $thresholdDays) {
            return [PSCustomObject]@{ Status = "ExpiringSoon"; DaysToExpiry = $daysToExpiry }
        }
        return [PSCustomObject]@{ Status = "Valid"; DaysToExpiry = $daysToExpiry }
    }

    $secretCredentials = 0
    $certificateCredentials = 0
    foreach ($app in $apps) {
        foreach ($secret in ($app.PasswordCredentials | Where-Object { $_.EndDateTime })) {
            $status = & $getExpiryStatus $secret.EndDateTime
            $secretCredentials++
            $rows += [PSCustomObject]@{
                AppObjectId     = $app.Id
                AppId           = $app.AppId
                DisplayName     = $app.DisplayName
                CredentialType  = "Secret"
                CredentialId    = $secret.KeyId
                StartDateTime   = $secret.StartDateTime
                EndDateTime     = $secret.EndDateTime
                Status          = $status.Status
                DaysToExpiry    = $status.DaysToExpiry
            }
        }

        foreach ($cert in ($app.KeyCredentials | Where-Object { $_.EndDateTime })) {
            $status = & $getExpiryStatus $cert.EndDateTime
            $certificateCredentials++
            $rows += [PSCustomObject]@{
                AppObjectId     = $app.Id
                AppId           = $app.AppId
                DisplayName     = $app.DisplayName
                CredentialType  = "Certificate"
                CredentialId    = $cert.KeyId
                StartDateTime   = $cert.StartDateTime
                EndDateTime     = $cert.EndDateTime
                Status          = $status.Status
                DaysToExpiry    = $status.DaysToExpiry
            }
        }
    }

    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        applications = @($apps).Count
        secretCredentials = $secretCredentials
        certificateCredentials = $certificateCredentials
        rows = @($rows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $rows
}

function Get-GraphPermissionsExport {
    <#
    .SYNOPSIS
    Builds a Microsoft Graph permissions inventory.
    Exports granted Graph application permissions for service principals and managed identities.

    .EXAMPLE
    Get-GraphPermissionsExport
    #>
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null

    $graphResourceAppId = '00000003-0000-0000-c000-000000000000'
    $rows = New-Object 'System.Collections.Generic.List[object]'

    $graphSpCandidates = @(
        Get-MgServicePrincipal -Filter "appId eq '$graphResourceAppId'" -All -Property "id,appId,displayName,appRoles,oauth2PermissionScopes"
    )
    if ($graphSpCandidates.Count -ne 1) {
        throw "Expected one Graph service principal for appId '$graphResourceAppId', found $($graphSpCandidates.Count)."
    }
    $graphSp = $graphSpCandidates[0]

    $appPermissionById = @{}
    foreach ($role in @($graphSp.AppRoles)) {
        if ($null -eq $role) { continue }
        if ($null -eq $role.Id) { continue }
        if (-not ($role.AllowedMemberTypes -contains 'Application')) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$role.Value)) { continue }
        $appPermissionById[$role.Id.ToString().ToLowerInvariant()] = [string]$role.Value
    }

    $delegatedPermissionById = @{}
    $delegatedPermissionIdByValue = @{}
    foreach ($scope in @($graphSp.Oauth2PermissionScopes)) {
        if ($null -eq $scope) { continue }
        if ($null -eq $scope.Id) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$scope.Value)) { continue }
        $scopeId = $scope.Id.ToString().ToLowerInvariant()
        $scopeValue = [string]$scope.Value
        $delegatedPermissionById[$scopeId] = $scopeValue
        $delegatedPermissionIdByValue[$scopeValue.ToLowerInvariant()] = $scopeId
    }

    $getRiskMetadata = {
        param([string]$Permission)
        $reasons = @()
        if (-not [string]::IsNullOrWhiteSpace($Permission)) {
            if ($Permission -imatch 'write') {
                $reasons += 'ContainsWrite'
            }
            if ($Permission -imatch 'delete') {
                $reasons += 'ContainsDelete'
            }
        }

        return [PSCustomObject]@{
            HasWriteOrDeleteCapability = ($reasons.Count -gt 0)
            RiskReason                 = ($reasons -join ';')
        }
    }

    $addRow = {
        param(
            [string]$EntityType,
            [string]$DisplayName,
            [string]$ObjectId,
            [string]$AppId,
            [string]$Permission,
            [string]$PermissionId
        )
        $risk = & $getRiskMetadata $Permission
        $rows.Add([PSCustomObject]@{
            EntityType                  = $EntityType
            DisplayName                 = $DisplayName
            ObjectId                    = $ObjectId
            AppId                       = $AppId
            Permission                  = $Permission
            PermissionId                = $PermissionId
            HasWriteOrDeleteCapability  = $risk.HasWriteOrDeleteCapability
            RiskReason                  = $risk.RiskReason
        }) | Out-Null
    }

    $principalSpCache = @{}
    $grantedPrincipalRows = 0
    $grantedAssignments = @(
        Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $graphSp.Id -All -Property 'id,appRoleId,principalId,principalType,principalDisplayName'
    )
    foreach ($assignment in $grantedAssignments) {
        $principalType = [string](Get-ObjectPropertyValue -InputObject $assignment -Name 'principalType')
        if ($principalType -ne 'ServicePrincipal') {
            continue
        }

        $principalId = [string](Get-ObjectPropertyValue -InputObject $assignment -Name 'principalId')
        if ([string]::IsNullOrWhiteSpace($principalId)) {
            continue
        }

        $permissionId = [string](Get-ObjectPropertyValue -InputObject $assignment -Name 'appRoleId')
        if ([string]::IsNullOrWhiteSpace($permissionId)) {
            continue
        }

        $permission = $appPermissionById[$permissionId.ToLowerInvariant()]
        if ([string]::IsNullOrWhiteSpace($permission)) {
            $permission = "<unresolved:$permissionId>"
        }

        if (-not $principalSpCache.ContainsKey($principalId)) {
            try {
                $principalSpCache[$principalId] = Get-MgServicePrincipal -ServicePrincipalId $principalId -Property 'id,appId,displayName,servicePrincipalType,tags' -ErrorAction Stop
            } catch {
                $principalSpCache[$principalId] = $null
            }
        }
        $principalSp = $principalSpCache[$principalId]

        $displayName = [string](Get-ObjectPropertyValue -InputObject $assignment -Name 'principalDisplayName')
        $appId = $null
        $entityType = 'ServicePrincipal'
        if ($null -ne $principalSp) {
            $displayNameCandidate = [string](Get-ObjectPropertyValue -InputObject $principalSp -Name 'displayName')
            if (-not [string]::IsNullOrWhiteSpace($displayNameCandidate)) {
                $displayName = $displayNameCandidate
            }
            $appId = [string](Get-ObjectPropertyValue -InputObject $principalSp -Name 'appId')

            $servicePrincipalType = [string](Get-ObjectPropertyValue -InputObject $principalSp -Name 'servicePrincipalType')
            if ($servicePrincipalType -ieq 'ManagedIdentity') {
                $entityType = 'ManagedIdentity'
            }
        }

        $addRowParams = @{
            EntityType = $entityType
            DisplayName = $displayName
            ObjectId = $principalId
            AppId = $appId
            Permission = $permission
            PermissionId = $permissionId
        }
        & $addRow @addRowParams
        $grantedPrincipalRows++
    }

    $graphPermissionSortOrder = @(
        @{ Expression = 'HasWriteOrDeleteCapability'; Descending = $true }
        @{ Expression = 'EntityType'; Descending = $false }
        @{ Expression = 'DisplayName'; Descending = $false }
        @{ Expression = 'GrantType'; Descending = $false }
        @{ Expression = 'Permission'; Descending = $false }
    )
    $sortedRows = @($rows | Sort-Object $graphPermissionSortOrder)
    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        grantedAssignments = @($grantedAssignments).Count
        grantedPrincipalRows = $grantedPrincipalRows
        rows = @($sortedRows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $sortedRows
}

function Get-LicenseExport {
    <#
    .SYNOPSIS
    Builds the subscribed licenses capacity export dataset.
    Calculates total, assigned, and available units with friendly names and low-availability flags.

    .EXAMPLE
    Get-LicenseExport
    #>
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null

    $lowAvailableThreshold = Get-ExportIntSetting -ExportName 'LICENSES' -Name 'lowAvailableThreshold' -Default 5 -MinValue 0
    $friendlyNames = Get-LicenseFriendlyNameMap
    $skus = @(
        Get-MgSubscribedSku -All -Property 'skuId,skuPartNumber,consumedUnits,prepaidUnits' -ErrorAction Stop
    )
    $rows = @()

    $toInt = {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) {
            return 0
        }
        $parsed = 0
        if ([int]::TryParse($Value.ToString(), [ref]$parsed)) {
            return $parsed
        }
        return 0
    }

    foreach ($sku in $skus) {
        $skuId = [string](Get-ObjectPropertyValue -InputObject $sku -Name 'skuId')
        $skuPartNumber = [string](Get-ObjectPropertyValue -InputObject $sku -Name 'skuPartNumber')
        $prepaidUnits = Get-ObjectPropertyValue -InputObject $sku -Name 'prepaidUnits'

        $enabledUnits = & $toInt (Get-ObjectPropertyValue -InputObject $prepaidUnits -Name 'enabled')
        $warningUnits = & $toInt (Get-ObjectPropertyValue -InputObject $prepaidUnits -Name 'warning')
        $suspendedUnits = & $toInt (Get-ObjectPropertyValue -InputObject $prepaidUnits -Name 'suspended')
        $totalUnits = $enabledUnits + $warningUnits + $suspendedUnits
        $assignedUnits = & $toInt (Get-ObjectPropertyValue -InputObject $sku -Name 'consumedUnits')
        $availableUnits = $totalUnits - $assignedUnits

        $friendlyName = $null
        if (-not [string]::IsNullOrWhiteSpace($skuId) -and $friendlyNames.BySkuId.ContainsKey($skuId)) {
            $friendlyName = $friendlyNames.BySkuId[$skuId]
        } elseif (-not [string]::IsNullOrWhiteSpace($skuPartNumber) -and $friendlyNames.BySkuPartNumber.ContainsKey($skuPartNumber)) {
            $friendlyName = $friendlyNames.BySkuPartNumber[$skuPartNumber]
        }
        if ([string]::IsNullOrWhiteSpace($friendlyName)) {
            $friendlyName = $skuPartNumber
        }
        if ([string]::IsNullOrWhiteSpace($friendlyName)) {
            $friendlyName = $skuId
        }

        $rows += [PSCustomObject]@{
            SkuId = $skuId
            SkuPartNumber = $skuPartNumber
            FriendlyName = $friendlyName
            TotalUnits = $totalUnits
            AssignedUnits = $assignedUnits
            AvailableUnits = $availableUnits
            LowAvailableThreshold = $lowAvailableThreshold
            IsLowAvailability = ($availableUnits -lt $lowAvailableThreshold)
        }
    }

    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        skus = @($skus).Count
        rows = @($rows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $rows
}

function Get-InactiveEntraAdminAccountsExport {
    <#
    .SYNOPSIS
    Builds the inactive admin accounts export dataset.
    Correlates privileged role assignments with sign-in activity to identify inactive admin users.

    .EXAMPLE
    Get-InactiveEntraAdminAccountsExport
    #>
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null

    $inactiveThresholdDays = Get-ExportIntSetting -ExportName 'INACTIVEENTRAADMINS' -Name 'days' -Default 90 -MinValue 1
    $roleDefinitions = @(
        Get-MgRoleManagementDirectoryRoleDefinition -All -Property 'id,displayName' -ErrorAction Stop
    )
    $roleMap = @{}
    foreach ($role in $roleDefinitions) {
        $roleMap[$role.Id] = $role.DisplayName
    }

    $principalCache = @{}
    $adminUsers = @{}

    $addAdminAssignment = {
        param(
            [Parameter(Mandatory)]
            [object]$Assignment,
            [Parameter(Mandatory)]
            [string]$AssignmentType
        )
        $principalId = $Assignment.PrincipalId
        if ([string]::IsNullOrWhiteSpace($principalId)) {
            return
        }

        $principal = Resolve-PrincipalInfo -PrincipalId $principalId -Cache $principalCache
        if ($principal.PrincipalType -ne 'User') {
            return
        }

        if (-not $adminUsers.ContainsKey($principalId)) {
            $adminUsers[$principalId] = [PSCustomObject]@{
                RoleSet = @{}
                AssignmentTypeSet = @{}
            }
        }

        $entry = $adminUsers[$principalId]
        $roleName = $roleMap[$Assignment.RoleDefinitionId]
        if ([string]::IsNullOrWhiteSpace($roleName)) {
            $roleName = $Assignment.RoleDefinitionId
        }
        if (-not [string]::IsNullOrWhiteSpace($roleName)) {
            $entry.RoleSet[$roleName] = $true
        }
        $entry.AssignmentTypeSet[$AssignmentType] = $true
    }

    $activeAssignments = @(
        Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -All -Property 'principalId,roleDefinitionId,startDateTime,endDateTime' -ErrorAction Stop
    )
    $activeAssignmentCount = @($activeAssignments).Count
    foreach ($assignment in $activeAssignments) {
        & $addAdminAssignment -Assignment $assignment -AssignmentType 'Active'
    }

    $eligibleAssignments = @(
        Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -All -Property 'principalId,roleDefinitionId,startDateTime,endDateTime' -ErrorAction Stop
    )
    $eligibleAssignmentCount = @($eligibleAssignments).Count
    foreach ($assignment in $eligibleAssignments) {
        & $addAdminAssignment -Assignment $assignment -AssignmentType 'Eligible'
    }

    $rows = @()
    $userLoadFailures = 0
    $nowUtc = (Get-Date).ToUniversalTime()
    foreach ($userId in ($adminUsers.Keys | Sort-Object)) {
        $entry = $adminUsers[$userId]
        $user = $null
        try {
            $userUri = ('https://graph.microsoft.com/v1.0/users/{0}?$select=id,userPrincipalName,displayName,accountEnabled,signInActivity' -f $userId)
            $user = Invoke-MgGraphRequest -Method GET -Uri $userUri -OutputType PSObject -ErrorAction Stop
        } catch {
            Write-Warning "Failed to load admin user '$userId': $($_.Exception.Message)"
            $userLoadFailures++
            continue
        }

        $signInActivity = Get-ObjectPropertyValue -InputObject $user -Name 'signInActivity'
        $lastSuccessful = ConvertTo-NullableUtcDateTime (Get-ObjectPropertyValue -InputObject $signInActivity -Name 'lastSuccessfulSignInDateTime')
        $lastInteractive = ConvertTo-NullableUtcDateTime (Get-ObjectPropertyValue -InputObject $signInActivity -Name 'lastSignInDateTime')
        $lastNonInteractive = ConvertTo-NullableUtcDateTime (Get-ObjectPropertyValue -InputObject $signInActivity -Name 'lastNonInteractiveSignInDateTime')

        $effectiveSignIn = $lastSuccessful
        if ($null -eq $effectiveSignIn) {
            $effectiveSignIn = Get-LatestDateTime -Values @($lastInteractive, $lastNonInteractive)
        }

        $daysSinceSignIn = $null
        $isInactive = $false
        $reason = $null
        if ($null -eq $effectiveSignIn) {
            $isInactive = $true
            $reason = 'NeverSignedIn'
        } else {
            $daysSinceSignIn = [math]::Floor(($nowUtc - $effectiveSignIn.ToUniversalTime()).TotalDays)
            if ($daysSinceSignIn -ge $inactiveThresholdDays) {
                $isInactive = $true
                $reason = 'InactiveThresholdExceeded'
            }
        }

        if (-not $isInactive) {
            continue
        }

        $roleNames = @($entry.RoleSet.Keys | Sort-Object) -join ';'
        $assignmentTypes = @($entry.AssignmentTypeSet.Keys | Sort-Object) -join ';'

        $rows += [PSCustomObject]@{
            UserId = [string](Get-ObjectPropertyValue -InputObject $user -Name 'id')
            UserPrincipalName = [string](Get-ObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
            DisplayName = [string](Get-ObjectPropertyValue -InputObject $user -Name 'displayName')
            AccountEnabled = (Get-ObjectPropertyValue -InputObject $user -Name 'accountEnabled')
            RoleNames = $roleNames
            AssignmentTypes = $assignmentTypes
            LastSuccessfulSignInDateTime = $lastSuccessful
            LastInteractiveSignInDateTime = $lastInteractive
            LastNonInteractiveSignInDateTime = $lastNonInteractive
            DaysSinceSignIn = $daysSinceSignIn
            InactiveThresholdDays = $inactiveThresholdDays
            IsInactive = $isInactive
            InactivityReason = $reason
        }
    }

    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        activeAssignments = $activeAssignmentCount
        eligibleAssignments = $eligibleAssignmentCount
        adminUsers = @($adminUsers.Keys).Count
        userLoadFailures = $userLoadFailures
        rows = @($rows).Count
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $rows
}

function Get-AccountMatchReasons {
    <#
    .SYNOPSIS
    Evaluates account naming rules and returns matched reasons.
    #>
    param(
        [AllowNull()][string]$UserPrincipalName,
        [AllowNull()][string]$DisplayName,
        [Parameter(Mandatory)][hashtable]$Rules
    )

    $reasons = @()
    $upn = if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) { '' } else { $UserPrincipalName.Trim().ToLowerInvariant() }
    $name = if ([string]::IsNullOrWhiteSpace($DisplayName)) { '' } else { $DisplayName.Trim().ToLowerInvariant() }

    foreach ($needle in @($Rules.upnStartsWith)) {
        if (-not [string]::IsNullOrWhiteSpace($upn) -and $upn.StartsWith($needle, [System.StringComparison]::Ordinal)) {
            $reasons += "upnStartsWith:$needle"
        }
    }
    foreach ($needle in @($Rules.upnContains)) {
        if (-not [string]::IsNullOrWhiteSpace($upn) -and $upn.Contains($needle)) {
            $reasons += "upnContains:$needle"
        }
    }
    foreach ($needle in @($Rules.displayNameContains)) {
        if (-not [string]::IsNullOrWhiteSpace($name) -and $name.Contains($needle)) {
            $reasons += "displayNameContains:$needle"
        }
    }

    return @($reasons | Select-Object -Unique)
}

function Get-AccountMatchPropertyPlan {
    <#
    .SYNOPSIS
    Builds select and output mappings for account match export properties.
    #>
    param(
        [AllowNull()]
        [object[]]$Properties
    )

    $selectProperties = @()
    $outputMappings = @()

    foreach ($rawPropertyName in @($Properties)) {
        $propertyName = [string]$rawPropertyName
        if ([string]::IsNullOrWhiteSpace($propertyName)) {
            continue
        }
        $propertyName = $propertyName.Trim()
        $normalizedPropertyName = $propertyName.ToLowerInvariant()

        if ($normalizedPropertyName -eq 'userid') {
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'UserId'
                SourceProperty = 'id'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'userprincipalname') {
            $selectProperties += 'userPrincipalName'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'UserPrincipalName'
                SourceProperty = 'userPrincipalName'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'displayname') {
            $selectProperties += 'displayName'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'DisplayName'
                SourceProperty = 'displayName'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'mail') {
            $selectProperties += 'mail'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'Mail'
                SourceProperty = 'mail'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'usertype') {
            $selectProperties += 'userType'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'UserType'
                SourceProperty = 'userType'
                NestedProperty = $null
            }
            continue
        }
        if ($normalizedPropertyName -eq 'accountenabled') {
            $selectProperties += 'accountEnabled'
            $outputMappings += [PSCustomObject]@{
                OutputName     = 'AccountEnabled'
                SourceProperty = 'accountEnabled'
                NestedProperty = $null
            }
            continue
        }

        if ($normalizedPropertyName -match '^extensionattribute([1-9]|1[0-5])$') {
            $attributeName = "extensionAttribute$($Matches[1])"
            $selectProperties += 'onPremisesExtensionAttributes'
            $outputMappings += [PSCustomObject]@{
                OutputName     = $propertyName
                SourceProperty = 'onPremisesExtensionAttributes'
                NestedProperty = $attributeName
            }
            continue
        }

        if ($normalizedPropertyName -match '^onpremisesextensionattributes\.(extensionattribute([1-9]|1[0-5]))$') {
            $attributeName = "extensionAttribute$($Matches[2])"
            $selectProperties += 'onPremisesExtensionAttributes'
            $outputMappings += [PSCustomObject]@{
                OutputName     = $propertyName
                SourceProperty = 'onPremisesExtensionAttributes'
                NestedProperty = $attributeName
            }
            continue
        }

        $selectProperties += $propertyName
        $outputMappings += [PSCustomObject]@{
            OutputName     = $propertyName
            SourceProperty = $propertyName
            NestedProperty = $null
        }
    }

    return [PSCustomObject]@{
        SelectProperties = @($selectProperties | Select-Object -Unique)
        OutputMappings   = @($outputMappings)
    }
}

function Get-AccountMatchesExport {
    <#
    .SYNOPSIS
    Builds an account inventory export dataset based on naming rules.

    .EXAMPLE
    Get-AccountMatchesExport -ExportName 'ACCOUNTMATCH_ADM'
    #>
    param([Parameter(Mandatory)][string]$ExportName)

    $normalizedExportName = $ExportName.Trim().ToUpperInvariant()
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Write-ExportRuntimeLog -Stage 'collect' -Event 'start' -Status 'ok'
    Connect-ToMicrosoftGraph | Out-Null

    $requestedProperties = @(
        ConvertTo-NormalizedStringList -InputValues @(
            Get-ExportSetting -ExportName $normalizedExportName -Name 'properties' -Default @()
        ) -SplitCsv
    )
    # Always include user identity in ACCOUNTMATCH_* exports.
    if (-not (@($requestedProperties | Where-Object { $_.ToLowerInvariant() -eq 'userid' }).Count -gt 0)) {
        $requestedProperties = @('UserId') + $requestedProperties
    }

    $rules = @{
        upnStartsWith = @(
            ConvertTo-NormalizedStringList -InputValues @(
                Get-ExportSetting -ExportName $normalizedExportName -Name 'upnStartsWith' -Default @()
            ) -SplitCsv | ForEach-Object { $_.ToLowerInvariant() }
        )
        upnContains = @(
            ConvertTo-NormalizedStringList -InputValues @(
                Get-ExportSetting -ExportName $normalizedExportName -Name 'upnContains' -Default @()
            ) -SplitCsv | ForEach-Object { $_.ToLowerInvariant() }
        )
        displayNameContains = @(
            ConvertTo-NormalizedStringList -InputValues @(
                Get-ExportSetting -ExportName $normalizedExportName -Name 'displayNameContains' -Default @()
            ) -SplitCsv | ForEach-Object { $_.ToLowerInvariant() }
        )
    }

    $ruleCount = @($rules.upnStartsWith).Count + @($rules.upnContains).Count + @($rules.displayNameContains).Count
    if ($ruleCount -eq 0) {
        Write-Warning "$normalizedExportName export has no matching rules configured. Set upnStartsWith/upnContains/displayNameContains."
        Write-ExportRuntimeLog -Stage 'collect' -Event 'rules_empty' -Status 'warn'
    }

    $rows = @()
    $propertyPlan = $null
    $remainingProperties = @($requestedProperties)
    $usersProcessed = 0
    while ($true) {
        $propertyPlan = Get-AccountMatchPropertyPlan -Properties $remainingProperties
        if (@($propertyPlan.OutputMappings).Count -eq 0) {
            Write-Warning "$normalizedExportName export has no valid properties after filtering invalid properties."
            Write-ExportRuntimeLog -Stage 'collect' -Event 'skipped_no_valid_properties' -Status 'warn'
            return @()
        }

        $rows = @()
        $usersProcessed = 0
        $selectProperties = @('id', 'userPrincipalName', 'displayName') + $propertyPlan.SelectProperties | Select-Object -Unique
        $selectQuery = [string]::Join(',', $selectProperties)
        $nextLink = "https://graph.microsoft.com/v1.0/users?`$select=$selectQuery&`$top=999"
        $retryRequired = $false

        do {
            $page = $null
            try {
                $page = Invoke-MgGraphRequest -Method GET -Uri $nextLink -OutputType PSObject -ErrorAction Stop
            } catch {
                $invalidProperty = Get-InvalidSelectPropertyNameFromError -ErrorRecord $_
                if ([string]::IsNullOrWhiteSpace($invalidProperty)) {
                    throw "Failed loading $normalizedExportName users with select '$selectQuery': $($_.Exception.Message)"
                }

                $invalidLookup = $invalidProperty.Trim().ToLowerInvariant()
                $filteredProperties = @($remainingProperties | Where-Object { $_.ToLowerInvariant() -ne $invalidLookup })
                if (@($filteredProperties).Count -eq @($remainingProperties).Count) {
                    throw "Failed loading $normalizedExportName users with select '$selectQuery': $($_.Exception.Message)"
                }

                Write-Warning "$normalizedExportName property '$invalidProperty' is invalid and will be skipped."
                Write-ExportRuntimeLog -Stage 'collect' -Event 'property_removed_invalid' -Status 'warn' -Data @{
                    property = $invalidProperty
                }
                $remainingProperties = $filteredProperties
                $retryRequired = $true
                break
            }

            $pageUsers = @(
                Get-ObjectPropertyValue -InputObject $page -Name 'value'
            )
            foreach ($user in $pageUsers) {
                $usersProcessed++
                $userPrincipalName = [string](Get-ObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
                $displayName = [string](Get-ObjectPropertyValue -InputObject $user -Name 'displayName')
                $matchReasons = Get-AccountMatchReasons -UserPrincipalName $userPrincipalName -DisplayName $displayName -Rules $rules
                $isMatch = @($matchReasons).Count -gt 0
                if (-not $isMatch) {
                    continue
                }

                $row = [ordered]@{
                    __SortUserPrincipalName = $userPrincipalName
                    __SortDisplayName = $displayName
                }
                foreach ($propertyMapping in $propertyPlan.OutputMappings) {
                    $value = $null
                    if (Test-HasUsableValue -Value $propertyMapping.NestedProperty) {
                        $parentObject = Get-ObjectPropertyValue -InputObject $user -Name $propertyMapping.SourceProperty
                        $value = Get-ObjectPropertyValue -InputObject $parentObject -Name $propertyMapping.NestedProperty
                    } else {
                        $value = Get-ObjectPropertyValue -InputObject $user -Name $propertyMapping.SourceProperty
                    }
                    $row[[string]$propertyMapping.OutputName] = $value
                }
                $rows += [PSCustomObject]$row
            }

            $nextLink = [string](Get-ObjectPropertyValue -InputObject $page -Name '@odata.nextLink')
            if ([string]::IsNullOrWhiteSpace($nextLink)) {
                $nextLink = $null
            }
        } while ($null -ne $nextLink)

        if (-not $retryRequired) {
            break
        }
    }

    $sortedRows = @(
        $rows |
            Sort-Object __SortUserPrincipalName, __SortDisplayName |
            ForEach-Object {
                $cleanRow = [ordered]@{}
                foreach ($prop in $_.PSObject.Properties) {
                    if (-not $prop.Name.StartsWith('__', [System.StringComparison]::Ordinal)) {
                        $cleanRow[[string]$prop.Name] = $prop.Value
                    }
                }
                [PSCustomObject]$cleanRow
            }
    )
    Write-ExportRuntimeLog -Stage 'collect' -Event 'summary' -Status 'ok' -Data @{
        usersProcessed = $usersProcessed
        rows = @($sortedRows).Count
        ruleCount = $ruleCount
        durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
    }
    return $sortedRows
}

function Invoke-Export {
    <#
    .SYNOPSIS
    Orchestrates export execution and storage writing for an export.
    Enforces enablement/no-data guards and routes export output to the standard storage pipeline.

    .EXAMPLE
    Invoke-Export -ExportName 'SUBSCRIPTIONS' -FetchData { Get-SubscriptionsExport }
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ExportName,
        [Parameter(Mandatory)]
        [scriptblock]$FetchData
    )
    $normalizedExportName = $ExportName.ToUpperInvariant()
    $runId = New-ExportRunId
    $startedAtUtc = (Get-Date).ToUniversalTime()
    Set-ExportRunContext -ExportName $normalizedExportName -RunId $runId
    Write-ExportRuntimeLog -Stage 'invoke' -Event 'start' -Status 'ok'

    try {
        if (-not (Test-ExportEnabled -ExportName $normalizedExportName)) {
            Write-Host "Export '$normalizedExportName' is disabled."
            Write-ExportRuntimeLog -Stage 'invoke' -Event 'skipped' -Status 'warn' -Data @{
                reason = 'disabled'
            }
            return
        }

        $data = @(& $FetchData)
        Write-ExportRuntimeLog -Stage 'invoke' -Event 'collect_completed' -Status 'ok' -Data @{
            rows = @($data).Count
        }

        if ($normalizedExportName -eq 'GROUPMEMBERS') {
            $rows = @($data)
            $groupIds = @(
                $rows |
                    ForEach-Object {
                        $partitionGroupId = [string](Get-ObjectPropertyValue -InputObject $_ -Name '__PartitionGroupId')
                        if (-not [string]::IsNullOrWhiteSpace($partitionGroupId)) {
                            $partitionGroupId
                        } else {
                            [string](Get-ObjectPropertyValue -InputObject $_ -Name 'GroupId')
                        }
                    } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Select-Object -Unique
            )
            if ($groupIds.Count -eq 0) {
                $groupIds = Resolve-GroupMemberExportGroupIds
            }
            if ($groupIds.Count -eq 0) {
                Write-ExportRuntimeLog -Stage 'invoke' -Event 'skipped' -Status 'warn' -Data @{
                    reason = 'no_groups'
                }
                return
            }

            $baseBlobPrefix = [string](Get-ExportSetting -ExportName 'GROUPMEMBERS' -Name 'blobPrefix' -Default $normalizedExportName.ToLowerInvariant())
            $partitionsWritten = 0
            $partitionsWithRows = 0
            $blobsWritten = 0
            foreach ($groupId in $groupIds) {
                $groupRows = @(
                    $rows |
                        Where-Object {
                            $partitionGroupId = [string](Get-ObjectPropertyValue -InputObject $_ -Name '__PartitionGroupId')
                            if (-not [string]::IsNullOrWhiteSpace($partitionGroupId)) {
                                $partitionGroupId -eq $groupId
                            } else {
                                ([string](Get-ObjectPropertyValue -InputObject $_ -Name 'GroupId')) -eq $groupId
                            }
                        } |
                        ForEach-Object {
                            $cleanRow = [ordered]@{}
                            foreach ($prop in $_.PSObject.Properties) {
                                if (-not $prop.Name.StartsWith('__', [System.StringComparison]::Ordinal)) {
                                    $cleanRow[[string]$prop.Name] = $prop.Value
                                }
                            }
                            [PSCustomObject]$cleanRow
                        }
                )
                if ($groupRows.Count -gt 0) {
                    $partitionsWithRows++
                }
                $groupBlobPrefix = if ([string]::IsNullOrWhiteSpace($baseBlobPrefix)) {
                    $groupId
                } else {
                    $baseBlobPrefix.TrimEnd('/') + '/' + $groupId
                }
                $groupMemberWriteParams = @{
                    ExportName = $normalizedExportName
                    Data = $groupRows
                    BlobPrefix = $groupBlobPrefix
                    FileNameBase = ("groupmembers_{0}" -f $groupId)
                }
                $blobsWritten += (Write-ExportToStorage @groupMemberWriteParams)
                $partitionsWritten++
            }
            if ($partitionsWithRows -eq 0) {
                Write-ExportRuntimeLog -Stage 'invoke' -Event 'no_data' -Status 'warn' -Data @{
                    reason = 'no_members'
                    partitions = $partitionsWritten
                }
            }
            Write-ExportRuntimeLog -Stage 'invoke' -Event 'complete' -Status 'ok' -Data @{
                rows = $rows.Count
                partitions = $partitionsWritten
                partitionsWithRows = $partitionsWithRows
                blobs = $blobsWritten
                durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
            }
            return
        }

        if ($normalizedExportName -eq 'AUGROUPMEMBERS') {
            $rows = @($data)
            $administrativeUnitIds = @(
                $rows |
                    ForEach-Object {
                        $partitionAdministrativeUnitId = [string](Get-ObjectPropertyValue -InputObject $_ -Name '__PartitionAdministrativeUnitId')
                        if (-not [string]::IsNullOrWhiteSpace($partitionAdministrativeUnitId)) {
                            $partitionAdministrativeUnitId
                        } else {
                            [string](Get-ObjectPropertyValue -InputObject $_ -Name 'AdministrativeUnitId')
                        }
                    } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
            if ($administrativeUnitIds.Count -eq 0) {
                Write-ExportRuntimeLog -Stage 'invoke' -Event 'no_data' -Status 'warn' -Data @{
                    reason = 'no_rows_after_collect'
                }
                return
            }

            $baseBlobPrefix = [string](Get-ExportSetting -ExportName 'AUGROUPMEMBERS' -Name 'blobPrefix' -Default $normalizedExportName.ToLowerInvariant())
            $partitionsWritten = 0
            $partitionsWithRows = 0
            $blobsWritten = 0
            foreach ($administrativeUnitId in $administrativeUnitIds) {
                $groupRows = @(
                    $rows |
                        Where-Object {
                            $partitionAdministrativeUnitId = [string](Get-ObjectPropertyValue -InputObject $_ -Name '__PartitionAdministrativeUnitId')
                            if (-not [string]::IsNullOrWhiteSpace($partitionAdministrativeUnitId)) {
                                $partitionAdministrativeUnitId -eq $administrativeUnitId
                            } else {
                                ([string](Get-ObjectPropertyValue -InputObject $_ -Name 'AdministrativeUnitId')) -eq $administrativeUnitId
                            }
                        } |
                        ForEach-Object {
                            $cleanRow = [ordered]@{}
                            foreach ($prop in $_.PSObject.Properties) {
                                if (-not $prop.Name.StartsWith('__', [System.StringComparison]::Ordinal)) {
                                    $cleanRow[[string]$prop.Name] = $prop.Value
                                }
                            }
                            [PSCustomObject]$cleanRow
                        }
                )
                if ($groupRows.Count -eq 0) {
                    continue
                }
                $partitionsWithRows++
                $groupBlobPrefix = if ([string]::IsNullOrWhiteSpace($baseBlobPrefix)) {
                    $administrativeUnitId.TrimEnd('/')
                } else {
                    $baseBlobPrefix.TrimEnd('/') + '/' + $administrativeUnitId
                }
                $auGroupMemberWriteParams = @{
                    ExportName = $normalizedExportName
                    Data = $groupRows
                    BlobPrefix = $groupBlobPrefix
                    FileNameBase = ("augroupmembers_{0}" -f $administrativeUnitId)
                }
                $blobsWritten += (Write-ExportToStorage @auGroupMemberWriteParams)
                $partitionsWritten++
            }
            if ($partitionsWithRows -eq 0) {
                Write-ExportRuntimeLog -Stage 'invoke' -Event 'no_data' -Status 'warn' -Data @{
                    reason = 'no_rows_for_partition'
                    partitions = $partitionsWritten
                }
            }
            Write-ExportRuntimeLog -Stage 'invoke' -Event 'complete' -Status 'ok' -Data @{
                rows = $rows.Count
                partitions = $partitionsWritten
                partitionsWithRows = $partitionsWithRows
                blobs = $blobsWritten
                durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
            }
            return
        }

        if (-not $data -or $data.Count -eq 0) {
            Write-Host "Export '$normalizedExportName' returned no data."
            Write-ExportRuntimeLog -Stage 'invoke' -Event 'no_data' -Status 'warn' -Data @{
                reason = 'no_rows_after_collect'
            }
            return
        }

        $blobsWritten = Write-ExportToStorage -ExportName $normalizedExportName -Data $data
        Write-ExportRuntimeLog -Stage 'invoke' -Event 'complete' -Status 'ok' -Data @{
            rows = @($data).Count
            blobs = $blobsWritten
            durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
        }
    } catch {
        Write-ExportRuntimeLog -Stage 'invoke' -Event 'failed' -Status 'error' -Data @{
            message = $_.Exception.Message
            durationMs = (Get-ElapsedMilliseconds -StartedAtUtc $startedAtUtc)
        }
        throw
    } finally {
        Clear-ExportRunContext
    }
}

Export-ModuleMember -Function @(
    'Invoke-Export',
    'Get-ConfiguredExportNamesByPrefix',
    'Get-RoleAssignmentsExport',
    'Get-AccountMatchesExport',
    'Get-GroupMembersExport',
    'Get-AuGroupMembersExport',
    'Get-SubscriptionsExport',
    'Get-AppRegistrationsExport',
    'Get-GraphPermissionsExport',
    'Get-LicenseExport',
    'Get-InactiveEntraAdminAccountsExport'
)





