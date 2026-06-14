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

See also:
- https://github.com/aarongodin/jsonschema (dormant since June 2022, has composite schemas but no `$ref` support)
- https://github.com/cyangle/json_schemer.cr (active, Draft 2020-12 compliant, has `$ref` - worth watching)

### Semantic Command Discovery ("Bash Spell Checker")

Use Jargon's JSON Schema definitions as a corpus for semantic search over CLI tools. Natural language → tool call translation without an LLM.

**Concept:**
```
$(repo push) → git push      # high confidence, auto-execute
$(delete old logs) → rm ...  # destructive, confirm first
```

**Techniques:**
- TF-IDF / co-occurrence vectors over tool schemas
- Embeddings over man pages and descriptions
- Salience scoring for match confidence

**Context signals to improve accuracy:**
- Current working directory (git repo? node project?)
- Recent bash history
- Cursor position in IDE/Vim
- Active file types

**Use case:** People who know what they want but forget exact syntax. Acts as a validator/refinement layer for LLM-generated commands - LLM gets close, system finds exact match, gates unsafe operations.

**Not a priority now** - Jargon is the foundation (self-describing tools). This layer can come later. See also: memo, xerp projects.

### Dynamic Completion Follow-ups

Scoped out of the initial dynamic-completion work (v0.19.0). All are refinements, not blockers:

- **Nested-object field completers.** Completer paths currently target schema-root fields (flags/positionals) and `subcommand.field`. Completing a nested object field (e.g. `--a.b`) is not handled.
- **Subcommand abbreviation during completion.** The completion engine resolves subcommands by exact match only; abbreviations (which `parse` supports) aren't expanded when computing candidates.
- **bash 3.2 portability.** The generated bash shim uses `readarray` (bash 4+). macOS ships bash 3.2 by default — provide a `read`-loop fallback if that matters.
- **Streaming/lazy completer results.** Completer blocks return `Array(String)`; a truly lazy/streaming return isn't wired (the `ctx.partial` scoping already covers the main performance concern).

### Other Ideas

- Man page generation
- Config file generation from schema
- Shell completion for enum values with descriptions
