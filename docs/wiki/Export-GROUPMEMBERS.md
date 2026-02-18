# Export: GROUPMEMBERS

Exports transitive group membership for configured groups.

## Required config

- `groupIds` (array of Entra group object IDs)

## Optional config

- `properties` (explicit list of additional properties)
- `excludePropertiesByGroup` (group ID -> property list to remove)

## Output properties

- Base field always included: `UserId`
- Any valid configured properties from `properties`
- Invalid configured properties are skipped and logged

## Config example

```json
"GROUPMEMBERS": {
  "enabled": true,
  "groupIds": ["<group-id-1>", "<group-id-2>"],
  "properties": ["mail", "department", "jobTitle"],
  "excludePropertiesByGroup": {
    "<group-id-2>": ["department"]
  }
}
```

## Schedule

`EXPORT_GROUPMEMBERS_SCHEDULE`

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Export: AUGROUPMEMBERS](Export-AUGROUPMEMBERS.md)
