# TODO

## Completed

### Schema Mixins with $id/$ref/allOf (v0.12.0)

Support for sharing properties across subcommands using standard JSON Schema keywords.

```yaml
---
$id: global
properties:
  verbose: {type: boolean, short: v}
  config: {type: string, short: c}
---
$id: output
properties:
  format: {type: string, enum: [json, yaml, csv]}
---
name: fetch
allOf:
  - {$ref: global}
  - properties:
      url: {type: string}
---
name: export
allOf:
  - {$ref: global}
  - {$ref: output}
  - properties:
      file: {type: string}
```

- `$id` schemas (no `name`) are mixins - not registered as subcommands
- `$ref` in `allOf` resolves to mixins in the same file
- Properties are merged; `type: object` is inferred if missing
- Subcommands opt-in explicitly via `allOf`

## Future Ideas

### Standalone JSON Schema Validator Library

Consider spinning off the validation logic as a separate shard. Jargon already supports:

- Type validation (string, integer, number, boolean, array, object, null)
- `minimum`/`maximum`, `exclusiveMinimum`/`exclusiveMaximum`, `multipleOf`
- `minLength`/`maxLength`, `pattern`
- `minItems`/`maxItems`, `uniqueItems`
- `enum`, `const`
- `format` (email, uri, uuid, date, time, date-time, ipv4, ipv6, hostname)
- `$ref` to `$defs`
- `allOf` with local `$id`/`$ref` resolution

To be spec-complete, would need:
- `anyOf`, `oneOf`, `not`
- `if`/`then`/`else`
- `dependentRequired`, `dependentSchemas`

See also: https://github.com/aarongodin/jsonschema (dormant since June 2022, has composite schemas but no `$ref` support)

### Other Ideas

- Man page generation
- Config file generation from schema
- Shell completion for enum values with descriptions
