# Configuration Guide

This page explains how `function/exports.config.json` drives runtime behavior.

## Top-level shape

```json
{
  "defaults": {
    "formats": ["json", "csv", "html"],
    "storage": {
      "storageAccount": "<name>",
      "storageContainer": "exports"
    }
  },
  "exports": {
    "GROUPMEMBERS": {
      "enabled": true
    }
  }
}
```

## Common keys

- `enabled`: turns an export on/off.
- `formats`: `json`, `csv`, `html`.
- `blobPrefix`: output folder prefix in blob container.
- `storage.storageAccount`: destination account.
- `storage.storageContainer`: destination container.
- `storage.storageConnectionString`: optional explicit override.

## Report-specific keys

- `groupIds` for `GROUPMEMBERS`
- `administrativeUnitIds` for `AUGROUPMEMBERS`
- `upnStartsWith`, `upnContains`, `displayNameContains` for `ACCOUNTMATCH_*`
- `properties` for `GROUPMEMBERS`, `AUGROUPMEMBERS`, and `ACCOUNTMATCH_*`
- `excludePropertiesByGroup` for `GROUPMEMBERS`
- `expiryDays` for `APPREGS`
- `lowAvailableThreshold`, `friendlyNamesSourceUrl` for `LICENSES`
- `days` for `INACTIVEENTRAADMINS`

## ACCOUNTMATCH multiple profiles

Any export key starting with `ACCOUNTMATCH_` is included when `ExportAccountMatches` runs. Example:

- `ACCOUNTMATCH_ADM`
- `ACCOUNTMATCH_SVC`

Each profile has its own matcher rules and property list.

## Property behavior

For supported exports, `properties` is explicit opt-in:

- only configured properties are added (plus required base fields)
- invalid property names are skipped
- export continues and logs warning for dropped properties

Required base fields always included:

- `GROUPMEMBERS`: `UserId`
- `AUGROUPMEMBERS`: `AdministrativeUnitId`, `GroupId`, `GroupDisplayName`, `UserId`
- `ACCOUNTMATCH_*`: `UserId`

## Group-specific property exclusions

`excludePropertiesByGroup` removes configured properties for specific group IDs in `GROUPMEMBERS`.

Use this when one group has stricter privacy or local policy rules.

## Storage output naming

Each file is written as:

`<blobPrefix>/<fileNameBase>_<yyyyMMdd_HHmmss>.<format>`

## Related pages

- [Export: ACCOUNTMATCH](Export-ACCOUNTMATCH.md)
- [Export: GROUPMEMBERS](Export-GROUPMEMBERS.md)
- [Export: AUGROUPMEMBERS](Export-AUGROUPMEMBERS.md)
