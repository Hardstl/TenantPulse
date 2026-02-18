# Export: AUGROUPMEMBERS

Exports transitive membership for groups discovered inside configured Administrative Units.

## Required config

- `administrativeUnitIds` (array of AU object IDs)

## Optional config

- `properties`

## Output properties

Base fields always included:

- `AdministrativeUnitId`
- `GroupId`
- `GroupDisplayName`
- `UserId`

Plus valid configured `properties`.

Invalid configured properties are skipped and logged.

## Config example

```json
"AUGROUPMEMBERS": {
  "enabled": true,
  "administrativeUnitIds": ["<au-id>"],
  "properties": ["department"]
}
```

## Schedule

`EXPORT_AUGROUPMEMBERS_SCHEDULE`

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Troubleshooting](Troubleshooting.md)
