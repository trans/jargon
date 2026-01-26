# Jargon

*Define your CLI jargon with JSON Schema.*

A Crystal library that generates CLI interfaces from JSON Schema definitions. Define your data structure once in JSON Schema, get a CLI parser with validation for free.

## Features

- **Validation**: Required fields, enum values, type checking
- **Defaults**: Schema default values are applied automatically
- **Config files**: Load from `.config/` (XDG spec) with merge support
- **Help text**: Generated from schema descriptions
- **Auto help flags**: `--help` and `-h` detected automatically
- **Shell completions**: Generate completion scripts for bash, zsh, and fish
- **Positional args**: Non-flag arguments assigned by position (variadic supported)
- **Short flags**: Single-character flag aliases (`-v`, `-n 5`)
- **Subcommands**: Named sub-parsers with independent schemas (abbreviations supported)
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

# Create CLI and parse arguments
cli = Jargon.from_json(schema, "myapp")
result = cli.parse(ARGV)

if result.help_requested?
  puts cli.help
  exit 0
elsif result.valid?
  puts result.to_pretty_json
else
  STDERR.puts result.errors.join("\n")
  STDERR.puts cli.help
  exit 1
end
```

## YAML Schemas

Prefer YAML? Convert it to JSON:

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
require "yaml"
schema = File.read("schema.yaml")
json = YAML.parse(schema).to_json
cli = Jargon.from_json(json, "myapp")
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

cli = Jargon.from_json(schema)
result = cli.parse(["user.name=John", "user.email=john@example.com"])
# => {"user": {"name": "John", "email": "john@example.com"}}
```

## Supported Types

| JSON Schema Type | CLI Example | Notes |
|------------------|-------------|-------|
| `string` | `name=John` | Default type |
| `integer` | `count=42` | Parsed as Int64 |
| `number` | `rate=3.14` | Parsed as Float64 |
| `boolean` | `verbose=true` or `--verbose` | Flag style supported |
| `array` | `tags=a,b,c` | Comma-separated |
| `object` | `user.name=John` | Dot notation |

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

cli = Jargon.from_json(schema, "myapp")
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

cli = Jargon.from_json(schema, "cat")
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

cli = Jargon.from_json(schema, "myapp")
result = cli.parse(["-v", "-n", "5", "-o", "out.txt"])
# => {"verbose": true, "count": 5, "output": "out.txt"}
```

```sh
myapp -v -n 5 -o out.txt
myapp --verbose --count 5 --output out.txt  # equivalent
```

## Help Flags

Jargon automatically detects `--help` and `-h` flags:

```crystal
cli = Jargon.from_json(schema, "myapp")
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

```sh
myapp --help           # top-level help
myapp -h               # same
myapp fetch --help     # subcommand help
myapp config set -h    # nested subcommand help
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

cli = Jargon.from_json(schema)
result = cli.parse(["--help", "topic"])
result.help_requested?  # => false
result["help"].as_s     # => "topic"

result = cli.parse(["-h", "localhost"])
result["host"].as_s     # => "localhost"
```

## Shell Completions

Jargon can generate shell completion scripts for bash, zsh, and fish. The `--completions <shell>` flag is detected automatically:

```crystal
cli = Jargon.from_json(schema, "myapp")
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

## Subcommands

Create CLIs with subcommands, each with their own schema:

```crystal
cli = Jargon.new("myapp")

cli.subcommand("fetch", %({
  "type": "object",
  "positional": ["url"],
  "properties": {
    "url": {"type": "string", "description": "Resource URL"},
    "depth": {"type": "integer", "short": "d"}
  },
  "required": ["url"]
}))

cli.subcommand("save", %({
  "type": "object",
  "properties": {
    "message": {"type": "string", "short": "m"},
    "all": {"type": "boolean", "short": "a"}
  },
  "required": ["message"]
}))

result = cli.parse(ARGV)

case result.subcommand
when "fetch"
  url = result["url"].as_s
  depth = result["depth"]?.try(&.as_i64)
when "save"
  message = result["message"].as_s
  all = result["all"]?.try(&.as_bool) || false
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
config.subcommand("set", %({
  "type": "object",
  "positional": ["key", "value"],
  "properties": {
    "key": {"type": "string"},
    "value": {"type": "string"}
  },
  "required": ["key", "value"]
}))
config.subcommand("get", %({
  "type": "object",
  "positional": ["key"],
  "properties": {
    "key": {"type": "string"}
  }
}))

cli = Jargon.new("myapp")
cli.subcommand("config", config)
cli.subcommand("status", %({"type": "object", "properties": {}}))

result = cli.parse(ARGV)

case result.subcommand
when "config set"
  key = result["key"].as_s
  value = result["value"].as_s
when "config get"
  key = result["key"].as_s
when "status"
  # ...
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

cli.subcommand("index", %({...}))
cli.subcommand("query", %({
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

cli.subcommand("fetch", Jargon.merge(%({
  "type": "object",
  "positional": ["url"],
  "properties": {
    "url": {"type": "string"},
    "depth": {"type": "integer", "short": "d"}
  }
}), global))

cli.subcommand("sync", Jargon.merge(%({
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

cli = Jargon.from_json(schema, "myapp")
result = cli.parse(ARGV)
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

Load configuration from standard XDG locations with `load_config`:

```crystal
cli = Jargon.from_json(schema, "myapp")
config = cli.load_config  # Returns JSON::Any or nil
result = cli.parse(ARGV, defaults: config)
```

Paths searched (first found wins, or merged if `merge: true`):
1. `./.config/myapp.json` (project local)
2. `./.config/myapp/config.json` (project local, directory style)
3. `$XDG_CONFIG_HOME/myapp.json` (user global, typically `~/.config`)
4. `$XDG_CONFIG_HOME/myapp/config.json` (user global, directory style)

By default, configs are merged with project overriding user:

```crystal
# Merge all found configs (default) - project wins over user
config = cli.load_config

# Or first-found wins
config = cli.load_config(merge: false)
```

Example project config (`.config/myapp.json`):
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
result = cli.parse(ARGV, defaults: config)

# From JSON
config = JSON.parse(File.read("settings.json"))
result = cli.parse(ARGV, defaults: config)
```

## API

```crystal
# From JSON string
cli = Jargon.from_json(json_string, program_name)

# From file
cli = Jargon.from_file("schema.json", program_name)

# For subcommands (no root schema)
cli = Jargon.new(program_name)
cli.subcommand("name", json_schema_string)

# Merge global options into subcommand schema
merged = Jargon.merge(subcommand_schema, global_schema)

# Parse arguments
result = cli.parse(ARGV)
result = cli.parse(ARGV, defaults: config)  # with config defaults

# Config file loading
config = cli.load_config              # merge all found configs (project wins)
config = cli.load_config(merge: false) # first found wins
paths = cli.config_paths              # list of paths searched

# Check validity
result.valid?      # => true/false
result.errors      # => Array(String)

# Get data
result.to_json         # => compact JSON string
result.to_pretty_json  # => formatted JSON string
result["key"]          # => access values
result.subcommand      # => String? (nil if no subcommands)

# Help detection
result.help_requested?  # => true if --help/-h was passed
result.help_subcommand  # => String? (which subcommand's help, nil for top-level)

# Completion detection
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

```sh
crystal spec
```

## License

MIT
