# Architecture

TenantPulse is intentionally simple: small timer-triggered functions call a shared reporting module that handles config, data collection, and storage output.

## Components

- Azure Function App (PowerShell 7.4)
- Timer triggers in `function/*/function.json`
- Shared module in `function/Modules/Reporting/Reporting.psm1`
- Export config in `function/exports.config.json`
- Export storage account + container
- App Insights + Log Analytics

## Execution flow

1. Timer trigger fires using `%EXPORT_*_SCHEDULE%`.
2. Function `run.ps1` imports reporting module.
3. `Invoke-Export` resolves config + collector for export key.
4. Collector gets data from Microsoft Graph and/or Azure.
5. Writer emits selected formats (`json`, `csv`, `html`) to blob storage.

## Config model

- Global defaults: `defaults`
- Per-export config: `exports.<EXPORT_KEY>`
- `ACCOUNTMATCH_*` is discovered by prefix, so multiple profiles run in one invocation.

## Important behavior

- `GROUPMEMBERS` always includes `UserId`.
- `AUGROUPMEMBERS` always includes `AdministrativeUnitId`, `GroupId`, `GroupDisplayName`, `UserId`.
- `ACCOUNTMATCH_*` always includes `UserId`.
- If configured `properties` include invalid names, the export still runs, drops invalid properties, and logs warnings.

## Infra source of truth

`deploy/main.bicep` controls:

- Function App and storage resources
- managed identity
- app settings including all `EXPORT_*_SCHEDULE`

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Exports Overview](Exports-Overview.md)
- [Security and Permissions](Security-and-Permissions.md)
