# Troubleshooting

## `Connect-MgGraph -Identity` fails

Check:

- Function App has system-assigned managed identity enabled
- Graph app roles were assigned to that identity
- Module restore completed for Graph modules

## Export produced no files

Check:

- Export `enabled` is `true`
- Function has a valid `EXPORT_*_SCHEDULE` app setting and the timer trigger is firing
- Scope values are valid (`groupIds`, `administrativeUnitIds`, match rules)
- Storage account/container config is correct
- Function logs for collector warnings/errors

## Expected property missing

For `GROUPMEMBERS`, `AUGROUPMEMBERS`, and `ACCOUNTMATCH_*`:

- only configured `properties` are exported (plus required base fields)
- invalid property names are dropped and logged
- for `GROUPMEMBERS`, `excludePropertiesByGroup` may remove fields per group

## Storage authorization errors

Check managed identity RBAC on export storage account. `Storage Blob Data Contributor` is required for writing blobs.

## Related pages

- [Security and Permissions](Security-and-Permissions.md)
