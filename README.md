# CLJ

A Crystal library that generates CLI interfaces from JSON Schema definitions. Define your data structure once in JSON Schema, get a CLI parser with validation for free.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  clj:
    github: trans/clj
```

Then run `shards install`.

## Usage

```crystal
require "clj"

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
cli = CLJ.from_json(schema, "myapp")
result = cli.parse(ARGV)

if result.valid?
  puts result.to_pretty_json
else
  STDERR.puts result.errors.join("\n")
  STDERR.puts cli.help
  exit 1
end
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

cli = CLJ.from_json(schema)
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

cli = CLJ.from_json(schema, "myapp")
result = cli.parse(["input.txt", "output.txt", "--verbose"])
# => {"file": "input.txt", "output": "output.txt", "verbose": true}
```

```sh
myapp input.txt output.txt --verbose
```

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

cli = CLJ.from_json(schema, "myapp")
result = cli.parse(["-v", "-n", "5", "-o", "out.txt"])
# => {"verbose": true, "count": 5, "output": "out.txt"}
```

```sh
myapp -v -n 5 -o out.txt
myapp --verbose --count 5 --output out.txt  # equivalent
```

## Subcommands

Create CLIs with subcommands, each with their own schema:

```crystal
cli = CLJ.new("git")

cli.subcommand("clone", %({
  "type": "object",
  "positional": ["repository"],
  "properties": {
    "repository": {"type": "string", "description": "Repository URL"},
    "depth": {"type": "integer", "short": "d"}
  },
  "required": ["repository"]
}))

cli.subcommand("commit", %({
  "type": "object",
  "properties": {
    "message": {"type": "string", "short": "m"},
    "all": {"type": "boolean", "short": "a"}
  },
  "required": ["message"]
}))

result = cli.parse(ARGV)

case result.subcommand
when "clone"
  repo = result["repository"].as_s
  depth = result["depth"]?.try(&.as_i64)
when "commit"
  message = result["message"].as_s
  all = result["all"]?.try(&.as_bool) || false
end
```

```sh
git clone https://github.com/user/repo -d 1
git commit -m "Initial commit" -a
```

### Default Subcommand

Set a default subcommand to use when no subcommand name is given:

```crystal
cli = CLJ.new("xerp")

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

## Features

- **Validation**: Required fields, enum values, type checking
- **Defaults**: Schema default values are applied automatically
- **Help text**: Generated from schema descriptions
- **Positional args**: Non-flag arguments assigned by position
- **Short flags**: Single-character flag aliases (`-v`, `-n 5`)
- **Subcommands**: Named sub-parsers with independent schemas
- **Default subcommand**: Fall back to a subcommand when none specified
- **Stdin JSON**: Read arguments as JSON from stdin with `-`
- **$ref support**: Reuse definitions with `$ref: "#/$defs/typename"`

```crystal
# Enum validation
schema = %({
  "type": "object",
  "properties": {
    "color": {"type": "string", "enum": ["red", "green", "blue"]}
  }
})

# Default values
schema = %({
  "type": "object",
  "properties": {
    "format": {"type": "string", "default": "json"}
  }
})

# $ref for reusable types
schema = %({
  "type": "object",
  "properties": {
    "billing": {"$ref": "#/$defs/address"},
    "shipping": {"$ref": "#/$defs/address"}
  },
  "$defs": {
    "address": {
      "type": "object",
      "properties": {
        "street": {"type": "string"},
        "city": {"type": "string"}
      }
    }
  }
})
```

## API

```crystal
# From JSON string
cli = CLJ.from_json(json_string, program_name)

# From file
cli = CLJ.from_file("schema.json", program_name)

# For subcommands (no root schema)
cli = CLJ.new(program_name)
cli.subcommand("name", json_schema_string)

# Parse arguments
result = cli.parse(ARGV)

# Check validity
result.valid?      # => true/false
result.errors      # => Array(String)

# Get data
result.to_json         # => compact JSON string
result.to_pretty_json  # => formatted JSON string
result["key"]          # => access values
result.subcommand      # => String? (nil if no subcommands)

# Help text
cli.help  # => usage string with all options
```

## Development

```sh
crystal spec
```

## License

MIT
