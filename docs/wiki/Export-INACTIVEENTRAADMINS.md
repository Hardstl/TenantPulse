# Export: INACTIVEENTRAADMINS

Exports privileged users with inactivity based on sign-in activity.

## Optional config

- `days` (inactivity threshold)

## Config example

```json
"INACTIVEENTRAADMINS": {
  "enabled": true,
  "formats": ["json", "csv", "html"],
  "blobPrefix": "inactive-admins",
  "storage": {
    "storageAccount": "<export-storage-account>",
    "storageContainer": "exports"
  },
  "days": 90
}
```

## Typical output content

- Privileged role assignments
- Last sign-in data (when available)
- Inactivity status based on configured threshold

## Schedule

`EXPORT_INACTIVEENTRAADMINS_SCHEDULE`

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Security and Permissions](Security-and-Permissions.md)
