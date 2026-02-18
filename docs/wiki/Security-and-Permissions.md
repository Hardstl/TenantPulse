# Security and Permissions

TenantPulse relies on managed identity and least-privilege assignments where possible.

## Identity model

- Function App uses system-assigned managed identity
- No embedded credentials are required for Graph/Azure APIs in normal operation

## Microsoft Graph app roles used

From `deploy/2-assign-graph-permissions.ps1`:

- `AuditLog.Read.All`
- `Directory.Read.All`
- `LicenseAssignment.Read.All`
- `RoleAssignmentSchedule.Read.Directory`
- `RoleEligibilitySchedule.Read.Directory`
- `RoleManagement.Read.Directory`

## Azure RBAC expectations

- Export storage: write access for blobs
- Runtime storage: required function runtime access
- Subscription/management scope read rights for subscription/governance exports

## Related pages

- [Deployment](Deployment.md)
- [Troubleshooting](Troubleshooting.md)
