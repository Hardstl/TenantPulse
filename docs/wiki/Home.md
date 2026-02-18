# TenantPulse Wiki

Welcome to the TenantPulse wiki. If you are new here, this is the fastest way to understand what the project does, deploy it, and get useful exports out of it.

## What this wiki covers

- How the solution is built
- How to deploy and run it
- How `exports.config.json` works
- What each export does and what fields it outputs
- How to troubleshoot common failures

## Start here

1. [Getting Started](Getting-Started.md)
2. [Configuration Guide](Configuration-Guide.md)
3. [Deployment](Deployment.md)
4. [Exports Overview](Exports-Overview.md)

## Quick project summary

TenantPulse is an Azure Functions (PowerShell) solution that runs scheduled exports for Entra ID and Azure governance/security reporting. It writes `json`, `csv`, and `html` files to Azure Blob Storage.

Core building blocks:

- Function triggers in `function/*/run.ps1`
- Shared export logic in `function/Modules/Reporting/Reporting.psm1`
- Central report config in `function/exports.config.json`
- Infra and schedule defaults in `deploy/main.bicep`

## Export catalog

- `ENTRAROLEMEMBERS`
- `ACCOUNTMATCH_*` (multiple profiles supported, like `ACCOUNTMATCH_ADM`, `ACCOUNTMATCH_SVC`)
- `GROUPMEMBERS`
- `AUGROUPMEMBERS`
- `SUBSCRIPTIONS`
- `APPREGS`
- `GRAPHPERMS`
- `LICENSES`
- `INACTIVEENTRAADMINS`

See [Exports Overview](Exports-Overview.md) for details.

## Related pages

- [Architecture](Architecture.md)
- [Security and Permissions](Security-and-Permissions.md)
- [Troubleshooting](Troubleshooting.md)
- [FAQ](FAQ.md)
- [Wiki Publish Guide](Wiki-Publish-Guide.md)
