# TODO

## Schema Includes (Future)

Add `include` field for sharing properties across subcommands in multi-doc files.

Schemas starting with `@` are "mixins" - not registered as subcommands, only used for inclusion.

```yaml
---
name: @global
properties:
  verbose: {type: boolean, short: v}
  config: {type: string, short: c}
---
name: @output
properties:
  format: {type: string, enum: [json, yaml, csv]}
---
name: fetch
include: [@global]
properties:
  url: {type: string}
---
name: export
include: [@global, @output]
properties:
  file: {type: string}
```

- `fetch` gets: `verbose`, `config`, `url`
- `export` gets: `verbose`, `config`, `format`, `file`

### Why `@`?

- Can't conflict with real subcommands (`myapp @global` would require shell quoting)
- Reads like an annotation/decorator
- Clear visual distinction from regular subcommands

### Implementation Notes

- Schemas with `name` starting with `@` are not added to `@subcommands`
- Process `include` field before parsing properties
- Merge included properties first, then local properties override
- Support multiple includes, processed in order
- Error if included schema not found
