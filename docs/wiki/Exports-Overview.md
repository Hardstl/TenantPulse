# Exports Overview

This page maps each function to its report key and schedule setting.

| Function | Report Key | Schedule App Setting |
|---|---|---|
| `ExportEntraRoleMembers` | `ENTRAROLEMEMBERS` | `EXPORT_ENTRAROLEMEMBERS_SCHEDULE` |
| `ExportAccountMatches` | `ACCOUNTMATCH_*` | `EXPORT_ACCOUNTMATCH_SCHEDULE` |
| `ExportGroupMembers` | `GROUPMEMBERS` | `EXPORT_GROUPMEMBERS_SCHEDULE` |
| `ExportAuGroupMembers` | `AUGROUPMEMBERS` | `EXPORT_AUGROUPMEMBERS_SCHEDULE` |
| `ExportSubscriptions` | `SUBSCRIPTIONS` | `EXPORT_SUBSCRIPTIONS_SCHEDULE` |
| `ExportAppRegistrations` | `APPREGS` | `EXPORT_APPREGS_SCHEDULE` |
| `ExportGraphPermissions` | `GRAPHPERMS` | `EXPORT_GRAPHPERMS_SCHEDULE` |
| `ExportLicenses` | `LICENSES` | `EXPORT_LICENSES_SCHEDULE` |
| `ExportInactiveEntraAdmins` | `INACTIVEENTRAADMINS` | `EXPORT_INACTIVEENTRAADMINS_SCHEDULE` |

## Notes

- Schedules use Azure Functions six-field NCRONTAB in UTC.
- Most exports are single-key. `ACCOUNTMATCH_*` is multi-profile by key prefix.
- Output formats are configured per export.

## Export pages

- [Export: ENTRAROLEMEMBERS](Export-ENTRAROLEMEMBERS.md)
- [Export: ACCOUNTMATCH](Export-ACCOUNTMATCH.md)
- [Export: GROUPMEMBERS](Export-GROUPMEMBERS.md)
- [Export: AUGROUPMEMBERS](Export-AUGROUPMEMBERS.md)
- [Export: SUBSCRIPTIONS](Export-SUBSCRIPTIONS.md)
- [Export: APPREGS](Export-APPREGS.md)
- [Export: GRAPHPERMS](Export-GRAPHPERMS.md)
- [Export: LICENSES](Export-LICENSES.md)
- [Export: INACTIVEENTRAADMINS](Export-INACTIVEENTRAADMINS.md)
