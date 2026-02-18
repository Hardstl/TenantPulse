# Export: LICENSES

Exports subscribed SKU capacity and consumption with optional friendly-name mapping.

## Optional config

- `lowAvailableThreshold`
- `friendlyNamesSourceUrl`

## Config example

```json
"LICENSES": {
  "enabled": true,
  "formats": ["json", "csv", "html"],
  "blobPrefix": "licenses",
  "storage": {
    "storageAccount": "<export-storage-account>",
    "storageContainer": "exports"
  },
  "lowAvailableThreshold": 5,
  "friendlyNamesSourceUrl": "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"
}
```

## Typical output content

- SKU identifiers
- Friendly product names (when mapping available)
- Consumed vs enabled units
- Low available capacity flags

## Schedule

`EXPORT_LICENSES_SCHEDULE`

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Troubleshooting](Troubleshooting.md)
