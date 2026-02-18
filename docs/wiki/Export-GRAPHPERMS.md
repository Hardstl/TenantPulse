# Export: GRAPHPERMS

Exports Graph app permission grants for service principals and managed identities.

## Config example

```json
"GRAPHPERMS": {
  "enabled": true,
  "formats": ["json", "csv", "html"],
  "blobPrefix": "graph-permissions",
  "storage": {
    "storageAccount": "<export-storage-account>",
    "storageContainer": "exports"
  }
}
```

## Typical output content

- Principal/app identity details
- Granted Graph app roles
- Flags to help identify higher-risk grants

## Schedule

`EXPORT_GRAPHPERMS_SCHEDULE`

## Related pages

- [Security and Permissions](Security-and-Permissions.md)
