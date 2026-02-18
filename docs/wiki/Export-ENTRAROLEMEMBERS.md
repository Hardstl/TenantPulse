# Export: ENTRAROLEMEMBERS

Exports active and eligible Entra role assignments with resolved principal details.

## Required config

- `enabled`
- `blobPrefix`
- storage settings (in export or defaults)

## Config example

```json
"ENTRAROLEMEMBERS": {
  "enabled": true,
  "formats": ["json", "csv", "html"],
  "blobPrefix": "entra-role-members",
  "storage": {
    "storageAccount": "<export-storage-account>",
    "storageContainer": "exports"
  }
}
```

## Typical output content

- Role information
- Assignment type/scope
- Principal identity details

See sample files in `examples/ExportEntraRoleMembers/`.

## Schedule

`EXPORT_ENTRAROLEMEMBERS_SCHEDULE`

## Related pages

- [Exports Overview](Exports-Overview.md)
- [Security and Permissions](Security-and-Permissions.md)
