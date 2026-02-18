# Export: ACCOUNTMATCH

Runs one export per configured key that starts with `ACCOUNTMATCH_`.

## How matching works

A user is included when at least one configured rule matches:

- `upnStartsWith`
- `upnContains`
- `displayNameContains`

Rule checks are case-insensitive.

## Config example

```json
"ACCOUNTMATCH_ADM": {
  "enabled": true,
  "blobPrefix": "account-match-adm",
  "upnStartsWith": ["adm.", "admin."],
  "upnContains": [],
  "displayNameContains": ["admin"],
  "properties": ["UserType", "AccountEnabled"]
}
```

## Output properties

- Base field always included: `UserId`
- Additional fields come from configured `properties`
- Invalid property names are skipped and logged

## Notes

- Export outputs matched users only.
- You can define multiple profiles (`ACCOUNTMATCH_ADM`, `ACCOUNTMATCH_SVC`, etc.).

## Schedule

`EXPORT_ACCOUNTMATCH_SCHEDULE`

## Related pages

- [Configuration Guide](Configuration-Guide.md)
- [Troubleshooting](Troubleshooting.md)
