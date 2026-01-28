# Jargon

*Define your CLI jargon with JSON Schema.*

A Crystal library that generates CLI interfaces from JSON Schema definitions. Define your data structure once in JSON Schema, get a CLI parser with validation for free.

## Features

- **Validation**: Required fields, enum values, strict type checking
- **Defaults**: Schema defaults, config file defaults, environment variables
- **Config files**: Load from `.config/` (XDG spec) with deep merge support
- **Help text**: Generated from schema descriptions
- **Auto help flags**: `--help` and `-h` detected automatically
- **Shell completions**: Generate completion scripts for bash, zsh, and fish
- **Positional args**: Non-flag arguments assigned by position and variadic support.
- **Short flags**: Single-character flag aliases (`-v`, `-n 5`)
- **Boolean flags**: Support both `--verbose` and `--verbose false` styles
- **Subcommands**: Named sub-parsers with independent schemas (supports abbreviated invocations)
- **Default subcommand**: Fall back to a subcommand when none specified
- **Stdin JSON**: Read arguments as JSON from stdin with `-`
- **Typo suggestions**: "Did you mean?" for mistyped options
- **$ref support**: Reuse definitions with `$ref: "#/$defs/typename"`

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  jargon:
    github: trans/jargon
```

Then run `shards install`.

## Usage

```crystal
require "jargon"

# Define your schema
schema = %({
  "type": "object",
  "properties": {
    "name": {"type": "string", "description": "User name"},
    "age": {"type": "integer"},
    "verbose": {"type": "boolean"}
  },
  "required": ["name"]
})

# Create CLI and run
cli = Jargon.cli("myapp", json: schema)
cli.run do |result|
  puts result.to_pretty_json
end
```

The `run` method automatically handles:
- `--help` / `-h`: prints help and exits
- `--completions <shell>`: prints shell completion script and exits
- Validation errors: prints errors to STDERR and exits with code 1

## YAML Schemas

YAML schemas are supported directly:

```yaml
# schema.yaml
type: object
properties:
  name:
    type: string
    description: User name
  verbose:
    type: boolean
    short: v
required:
  - name
```

```crystal
schema = File.read("schema.yaml")
cli = Jargon.cli("myapp", yaml: schema)
```

## Argument Styles

Three styles are supported interchangeably:

```sh
# Equals style (minimal)
myapp name=John age=30 verbose=true

# Colon style
myapp name:John age:30 verbose:true

# Traditional style
myapp --name John --age 30 --verbose
```

Mix and match as you like:
```sh
myapp name=John --age 30 verbose:true
```

## Nested Objects

Use dot notation for nested properties:

```crystal
schema = %({
  "type": "object",
  "properties": {
    "user": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "email": {"type": "string"}
      }
    }
  }
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["user.name=John", "user.email=john@example.com"])
# => {"user": {"name": "John", "email": "john@example.com"}}
```

## Supported Types

| JSON Schema Type | CLI Example | Notes |
|------------------|-------------|-------|
| `string` | `name=John` | Default type |
| `integer` | `count=42` | Parsed as Int64, strict validation |
| `number` | `rate=3.14` | Parsed as Float64, strict validation |
| `boolean` | `verbose=true` or `--verbose` | Flag style supported |
| `array` | `tags=a,b,c` | Comma-separated |
| `object` | `user.name=John` | Dot notation |

### Boolean Flags

Boolean flags support multiple styles:

```sh
# Flag style (sets to true)
myapp --verbose

# Explicit value
myapp --verbose true
myapp --verbose false
myapp --enabled no

# Equals style
myapp verbose=true
myapp --verbose=false
```

Recognized boolean values: `true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0` (case-insensitive).

When a boolean flag is followed by a non-boolean value, the value is not consumed:

```sh
# --verbose is true, output.txt is a positional arg
myapp --verbose output.txt
```

### Strict Numeric Validation

Invalid numeric values produce clear error messages:

```sh
$ myapp --count abc
Error: Invalid integer value 'abc' for count

$ myapp --count 10x
Error: Invalid integer value '10x' for count
```

## Positional Arguments

Define positional arguments with the `positional` array:

```crystal
schema = %({
  "type": "object",
  "positional": ["file", "output"],
  "properties": {
    "file": {"type": "string", "description": "Input file"},
    "output": {"type": "string", "description": "Output file"},
    "verbose": {"type": "boolean"}
  },
  "required": ["file"]
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["input.txt", "output.txt", "--verbose"])
# => {"file": "input.txt", "output": "output.txt", "verbose": true}
```

```sh
myapp input.txt output.txt --verbose
```

### Variadic Positionals

When the last positional has `type: array`, it collects all remaining arguments:

```crystal
schema = %({
  "type": "object",
  "positional": ["files"],
  "properties": {
    "files": {"type": "array", "description": "Input files"},
    "number": {"type": "boolean", "short": "n"}
  }
})

cli = Jargon.cli("cat", json: schema)
result = cli.parse(["-n", "a.txt", "b.txt", "c.txt"])
# => {"number": true, "files": ["a.txt", "b.txt", "c.txt"]}
```

```sh
cat -n a.txt b.txt c.txt
```

Note: Flags should come before variadic positionals. Collection stops at the first flag encountered.

## Short Flags

Define short flag aliases with the `short` property:

```crystal
schema = %({
  "type": "object",
  "properties": {
    "verbose": {"type": "boolean", "short": "v"},
    "count": {"type": "integer", "short": "n"},
    "output": {"type": "string", "short": "o"}
  }
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["-v", "-n", "5", "-o", "out.txt"])
# => {"verbose": true, "count": 5, "output": "out.txt"}
```

```sh
myapp -v -n 5 -o out.txt
myapp --verbose --count 5 --output out.txt  # equivalent
```

## Help Flags

Jargon automatically detects `--help` and `-h` flags. When using `run`, help is printed and the program exits automatically:

```crystal
cli = Jargon.cli("myapp", json: schema)
cli.run do |result|
  # This block only runs if --help was NOT passed
  puts result.to_pretty_json
end
```

```sh
myapp --help           # top-level help
myapp -h               # same
myapp fetch --help     # subcommand help
myapp config set -h    # nested subcommand help
```

If you need manual control, use `parse` instead:

```crystal
result = cli.parse(ARGV)

if result.help_requested?
  if subcmd = result.help_subcommand
    puts cli.help(subcmd)
  else
    puts cli.help
  end
  exit 0
end
```

If you define a `help` property or use `-h` as a short flag for something else, Jargon won't intercept those flags:

```crystal
# User-defined help property takes precedence
schema = %({
  "type": "object",
  "properties": {
    "help": {"type": "string", "description": "Help topic"},
    "host": {"type": "string", "short": "h"}
  }
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["--help", "topic"])
result.help_requested?  # => false
result["help"].as_s     # => "topic"

result = cli.parse(["-h", "localhost"])
result["host"].as_s     # => "localhost"
```

## Shell Completions

Jargon can generate shell completion scripts for bash, zsh, and fish. When using `run`, the `--completions <shell>` flag is handled automatically:

### Installing Completions

Generate the completion script once and save it to your shell's completions directory:

```sh
# Bash
myapp --completions bash > ~/.local/share/bash-completion/completions/myapp

# Zsh (ensure ~/.zfunc is in your fpath)
myapp --completions zsh > ~/.zfunc/_myapp

# Fish
myapp --completions fish > ~/.config/fish/completions/myapp.fish
```

The generated scripts provide completions for:
- Subcommand names
- Long flags (`--verbose`, `--output`)
- Short flags (`-v`, `-o`)
- Enum values (e.g., `--format json|yaml|xml`)
- Nested subcommands

### Manual Completion Handling

If you need manual control, use `parse`:

```crystal
cli = Jargon.cli("myapp", json: schema)
result = cli.parse(ARGV)

if result.completion_requested?
  case result.completion_shell
  when "bash" then puts cli.bash_completion
  when "zsh"  then puts cli.zsh_completion
  when "fish" then puts cli.fish_completion
  end
  exit 0
end
```

## Subcommands

Create CLIs with subcommands, each with their own schema:

```crystal
cli = Jargon.new("myapp")

cli.subcommand("fetch", json: %({
  "type": "object",
  "positional": ["url"],
  "properties": {
    "url": {"type": "string", "description": "Resource URL"},
    "depth": {"type": "integer", "short": "d"}
  },
  "required": ["url"]
}))

cli.subcommand("save", json: %({
  "type": "object",
  "properties": {
    "message": {"type": "string", "short": "m"},
    "all": {"type": "boolean", "short": "a"}
  },
  "required": ["message"]
}))

cli.run do |result|
  case result.subcommand
  when "fetch"
    url = result["url"].as_s
    depth = result["depth"]?.try(&.as_i64)
  when "save"
    message = result["message"].as_s
    all = result["all"]?.try(&.as_bool) || false
  end
end
```

```sh
myapp fetch https://example.com/resource -d 1
myapp save -m "Updated config" -a
```

### Nested Subcommands

Create nested subcommands by passing a `CLI` instance as the subcommand:

```crystal
config = Jargon.new("config")
config.subcommand("set", json: %({
  "type": "object",
  "positional": ["key", "value"],
  "properties": {
    "key": {"type": "string"},
    "value": {"type": "string"}
  },
  "required": ["key", "value"]
}))
config.subcommand("get", json: %({
  "type": "object",
  "positional": ["key"],
  "properties": {
    "key": {"type": "string"}
  }
}))

cli = Jargon.new("myapp")
cli.subcommand("config", config)
cli.subcommand("status", json: %({"type": "object", "properties": {}}))

cli.run do |result|
  case result.subcommand
  when "config set"
    key = result["key"].as_s
    value = result["value"].as_s
  when "config get"
    key = result["key"].as_s
  when "status"
    # ...
  end
end
```

```sh
myapp config set api_url https://api.example.com
myapp config get api_url
myapp status
```

The `result.subcommand` returns the full path as a space-separated string (e.g., `"config set"`).

### Default Subcommand

Set a default subcommand to use when no subcommand name is given:

```crystal
cli = Jargon.new("xerp")

cli.subcommand("index", json: %({...}))
cli.subcommand("query", json: %({
  "type": "object",
  "positional": ["query_text"],
  "properties": {
    "query_text": {"type": "string"},
    "top": {"type": "integer", "default": 10, "short": "n"}
  }
}))

cli.default_subcommand("query")
```

```sh
# These are equivalent:
xerp query "search term" -n 5
xerp "search term" -n 5
```

Note: If the first argument matches a subcommand name, it's treated as a subcommand, not as input to the default. Use the explicit form if you need to search for a term that matches a subcommand name.

### Global Options

Use `Jargon.merge` to add common options to all subcommands:

```crystal
global = %({
  "type": "object",
  "properties": {
    "verbose": {"type": "boolean", "short": "v", "description": "Verbose output"},
    "config": {"type": "string", "short": "c", "description": "Config file path"}
  }
})

cli = Jargon.new("myapp")

cli.subcommand("fetch", json: Jargon.merge(%({
  "type": "object",
  "positional": ["url"],
  "properties": {
    "url": {"type": "string"},
    "depth": {"type": "integer", "short": "d"}
  }
}), global))

cli.subcommand("sync", json: Jargon.merge(%({
  "type": "object",
  "properties": {
    "force": {"type": "boolean", "short": "f"}
  }
}), global))
```

```sh
myapp fetch https://example.com/data -v
myapp sync --force --config myconfig.json
```

Subcommand properties take precedence if there's a conflict with global properties.

### File-Based Subcommands

Load subcommands from external files for cleaner organization:

```crystal
cli = Jargon.new("myapp")
cli.subcommand("fetch", file: "schemas/fetch.yaml")
cli.subcommand("save", file: "schemas/save.json")
```

Or define all subcommands in a single multi-document file:

```yaml
# commands.yaml
---
name: fetch
type: object
properties:
  url: {type: string}
---
name: save
type: object
properties:
  file: {type: string}
```

```crystal
# Load as top-level subcommands
cli = Jargon.cli("myapp", file: "commands.yaml")
# or
cli = Jargon.new("myapp")
cli.subcommand(file: "commands.yaml")
```

Load multi-doc as nested subcommands by providing a parent name:

```crystal
cli = Jargon.new("myapp")
cli.subcommand("config", file: "config_commands.yaml")  # config get, config set, etc.
```

Multi-document format is auto-detected for `json:`, `yaml:`, and `file:` parameters. Each document must have a `name` field.

JSON uses relaxed JSONL (consecutive objects with whitespace):

```json
{
  "name": "fetch",
  "type": "object",
  "properties": {"url": {"type": "string"}}
}
{
  "name": "save",
  "type": "object",
  "properties": {"file": {"type": "string"}}
}
```

### JSON from Stdin

Use `-` to read JSON input from stdin:

```sh
# JSON with subcommand field
echo '{"subcommand": "query", "query_text": "search term", "top": 5}' | xerp -

# JSON args for explicit subcommand
echo '{"result_id": "abc123", "useful": true}' | xerp mark -
```

If no `subcommand` field is present in `xerp -`, the default subcommand is used (if set).

The field name is configurable:

```crystal
cli.subcommand_key("op")  # default is "subcommand"
```

```sh
echo '{"op": "query", "query_text": "search"}' | xerp -
```

## Environment Variables

Map schema properties to environment variables with the `env` property:

```crystal
schema = %({
  "type": "object",
  "properties": {
    "api-key": {"type": "string", "env": "MY_APP_API_KEY"},
    "host": {"type": "string", "env": "MY_APP_HOST", "default": "localhost"},
    "debug": {"type": "boolean", "env": "MY_APP_DEBUG"}
  }
})

cli = Jargon.cli("myapp", json: schema)
cli.run do |result|
  # result contains api-key, host from env, debug from CLI
end
```

```sh
export MY_APP_API_KEY=secret123
export MY_APP_HOST=prod.example.com
myapp --debug  # api-key and host from env, debug from CLI
```

Merge order (highest priority first):
1. CLI arguments
2. Environment variables
3. Config file defaults
4. Schema defaults

## Config Files

Load configuration from standard XDG locations with `load_config`. Supports YAML and JSON:

```crystal
cli = Jargon.cli("myapp", json: schema)
config = cli.load_config  # Returns JSON::Any or nil
cli.run(defaults: config) do |result|
  # ...
end
```

Paths searched (first found wins, or merged if `merge: true`):
1. `./.config/myapp.yaml` / `.yml` / `.json` (project local)
2. `./.config/myapp/config.yaml` / `.yml` / `.json` (project local, directory style)
3. `$XDG_CONFIG_HOME/myapp.yaml` / `.yml` / `.json` (user global, typically `~/.config`)
4. `$XDG_CONFIG_HOME/myapp/config.yaml` / `.yml` / `.json` (user global, directory style)

YAML is preferred over JSON when both exist at the same location.

By default, configs are deep-merged with project overriding user:

```crystal
# Merge all found configs (default) - project wins over user
config = cli.load_config

# Or first-found wins
config = cli.load_config(merge: false)
```

### Deep Merge

Nested objects are recursively merged, not overwritten:

```yaml
# User config (~/.config/myapp.yaml)
database:
  host: localhost
  port: 5432
  user: default_user

# Project config (.config/myapp.yaml)
database:
  host: production.example.com

# Result after merge:
database:
  host: production.example.com  # from project
  port: 5432                    # preserved from user
  user: default_user            # preserved from user
```

### Config Warnings

Invalid config files emit warnings to STDERR by default. To suppress:

```crystal
Jargon.config_warnings = false
config = cli.load_config
Jargon.config_warnings = true
```

Example project config (`.config/myapp.yaml`):
```yaml
host: localhost
port: 8080
debug: true
```

Or JSON (`.config/myapp.json`):
```json
{
  "host": "localhost",
  "port": 8080,
  "debug": true
}
```

The `defaults:` parameter accepts any JSON-like data, so you can load config however you prefer:

```crystal
# From YAML
config = YAML.parse(File.read("config.yaml"))
cli.run(defaults: config) { |result| ... }

# From JSON
config = JSON.parse(File.read("settings.json"))
cli.run(defaults: config) { |result| ... }
```

## API

```crystal
# Create CLI (program name first, named schema parameter)
cli = Jargon.cli(program_name, json: json_string)
cli = Jargon.cli(program_name, yaml: yaml_string)
cli = Jargon.cli(program_name, file: "schema.json")

# For subcommands (no root schema)
cli = Jargon.new(program_name)
cli.subcommand("name", json: schema_string)
cli.subcommand("name", yaml: schema_string)
cli.subcommand("name", file: "schema.yaml")      # single-doc file
cli.subcommand(file: "commands.yaml")            # multi-doc as top-level
cli.subcommand("parent", file: "commands.yaml")  # multi-doc as nested

# Merge global options into subcommand schema
merged = Jargon.merge(subcommand_schema, global_schema)

# Run with automatic help/completions/error handling (recommended)
cli.run { |result| puts result.to_pretty_json }
cli.run(ARGV) { |result| ... }
result = cli.run                      # without block, returns Result

# Parse arguments - returns Result with errors array
result = cli.parse(ARGV)
result = cli.parse(ARGV, defaults: config)

# Get data as JSON - returns JSON::Any, raises ParseError on errors
data = cli.json(ARGV)
data = cli.json(ARGV, defaults: config)

# Config file loading
config = cli.load_config              # merge all found configs (project wins)
config = cli.load_config(merge: false) # first found wins
paths = cli.config_paths              # list of paths searched

# Result methods (from parse or run)
result.valid?      # => true/false
result.errors      # => Array(String)
result.data        # => JSON::Any
result.to_json         # => compact JSON string
result.to_pretty_json  # => formatted JSON string
result["key"]          # => access values
result.subcommand      # => String? (nil if no subcommands)

# Help/completion detection (when using parse)
result.help_requested?  # => true if --help/-h was passed
result.help_subcommand  # => String? (which subcommand's help, nil for top-level)
result.completion_requested?  # => true if --completions was passed
result.completion_shell       # => String? ("bash", "zsh", or "fish")

# Help text
cli.help              # => usage string with all options
cli.help("fetch")     # => help for specific subcommand
cli.help("config set") # => help for nested subcommand

# Completion scripts
cli.bash_completion  # => bash completion script
cli.zsh_completion   # => zsh completion script
cli.fish_completion  # => fish completion script
```

## Development

### Prerequisites

- Crystal >= 1.18.2

### Running Tests

```sh
shards install
crystal spec
```

### Project Structure

```
src/
├── jargon.cr              # Main module, convenience methods
└── jargon/
    ├── cli.cr             # Core CLI parser
    ├── schema.cr          # JSON Schema parsing
    ├── schema/property.cr # Property definitions
    ├── result.cr          # Parse result container
    ├── config.cr          # Config file loading (XDG)
    ├── help.cr            # Help text generation
    └── completion.cr      # Shell completion scripts
spec/
└── jargon_spec.cr         # Test suite
```

### Building Docs

```sh
crystal docs
open docs/index.html
```

## License

MIT
