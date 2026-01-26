require "./jargon/schema"
require "./jargon/cli"
require "./jargon/result"
require "./jargon/completion"

module Jargon
  VERSION = "0.9.0"

  # Convenience method to create a CLI with just a program name (for subcommand mode)
  def self.new(program_name : String) : CLI
    CLI.new(program_name)
  end

  # Convenience method to create a CLI from a JSON schema string
  def self.from_json(json : String, program_name : String = "cli") : CLI
    schema = Schema.from_json(json)
    CLI.new(schema, program_name)
  end

  # Convenience method to create a CLI from a JSON schema file
  def self.from_file(path : String, program_name : String = "cli") : CLI
    schema = Schema.from_file(path)
    CLI.new(schema, program_name)
  end

  # Convenience shortcut with program name first
  def self.cli(program_name : String, *, json : String) : CLI
    CLI.from_json(json, program_name)
  end

  def self.cli(program_name : String, *, file : String) : CLI
    CLI.from_file(file, program_name)
  end

  # Merge global schema properties into a subcommand schema.
  # Properties from global are added to sub (sub takes precedence if both define same key).
  def self.merge(sub : String, global : String) : String
    sub_json = JSON.parse(sub).as_h
    global_json = JSON.parse(global).as_h

    sub_props = sub_json["properties"]?.try(&.as_h) || {} of String => JSON::Any
    global_props = global_json["properties"]?.try(&.as_h) || {} of String => JSON::Any

    # Global properties first, then sub properties override
    merged_props = global_props.merge(sub_props)
    sub_json["properties"] = JSON::Any.new(merged_props)

    sub_json.to_json
  end
end
