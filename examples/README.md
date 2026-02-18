# Export Examples

This folder contains per-function examples for:

- `exports.config.json` snippets (`exports.config.example.json`)
- Expected output shape samples (`output.sample.json`)

Notes:

- Examples are sanitized and use placeholder IDs/names.
- Output properties can vary by tenant data and optional config settings.
- Samples reflect current collector shapes in `function/Modules/Reporting/Reporting.psm1`.

## Function Map

- `ExportEntraRoles` -> `ENTRAROLES`
- `ExportGroupMembers` -> `GROUPMEMBERS`
- `ExportAuGroupMembers` -> `AUGROUPMEMBERS`
- `ExportSubscriptions` -> `SUBSCRIPTIONS`
- `ExportAppRegistrations` -> `APPREGS`
- `ExportGraphPermissions` -> `GRAPHPERMS`
- `ExportLicenses` -> `LICENSES`
- `ExportInactiveAdmins` -> `INACTIVEADMINS`
