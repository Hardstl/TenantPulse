# Export: SUBSCRIPTIONS

Exports Azure subscription inventory and related governance fields.

## Required config

- `enabled`

## Config example

```json
"SUBSCRIPTIONS": {
  "enabled": true,
  "formats": ["json", "csv", "html"],
  "blobPrefix": "subscriptions",
  "storage": {
    "storageAccount": "<export-storage-account>",
    "storageContainer": "exports"
  }
}
```

## Typical output content

- Subscription identifiers
- Display names
- State
- Tags

See sample files in `examples/ExportSubscriptions/`.

## Schedule

`EXPORT_SUBSCRIPTIONS_SCHEDULE`

## Related pages

- [Security and Permissions](Security-and-Permissions.md)
- [Troubleshooting](Troubleshooting.md)
