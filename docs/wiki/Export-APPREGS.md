# Export: APPREGS

Exports Entra app registration credential expiry information.

## Optional config

- `expiryDays` (look-ahead window for expiring credentials)

## Config example

```json
"APPREGS": {
  "enabled": true,
  "formats": ["json", "csv", "html"],
  "blobPrefix": "app-registrations",
  "storage": {
    "storageAccount": "<export-storage-account>",
    "storageContainer": "exports"
  },
  "expiryDays": 30
}
```

## Typical output content

- Application identifiers
- Credential type (secret/certificate)
- Start/end dates
- Expiry status flags

## Schedule

`EXPORT_APPREGS_SCHEDULE`

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Security and Permissions](Security-and-Permissions.md)
