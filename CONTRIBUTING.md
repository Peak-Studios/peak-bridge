# Contributing

Thanks for helping improve `peak-bridge`.

## Development

1. Keep changes scoped to the shared bridge layer.
2. Do not add resource-specific logic for one Peak product.
3. Prefer normalized exports that work across Qbox, QBCore, ESX, and standalone fallback.
4. Wrap third-party exports/events with `pcall` when they may be absent or version-dependent.
5. Update `README.md` and `CHANGELOG.md` when changing public APIs.

## Checks

Run:

```bash
npm run lint:lua
```

This parses all Lua files with `luaparse` to catch syntax errors.
