require "./jargon/schema"
require "./jargon/cli"
require "./jargon/result"
require "./jargon/completion"

module Jargon
  VERSION = "0.15.0"

  class ParseError < Exception
    getter errors : Array(String)

    def initialize(@errors : Array(String))
      super(@errors.join("\n"))
    end
  end

  # Convenience method to create a CLI with just a program name (for subcommand mode)
  def self.new(program_name : String) : CLI
    CLI.new(program_name)
  end

  @[Deprecated("Use Jargon.cli(program_name, json: schema) instead")]
  def self.from_json(json : String, program_name : String = "cli") : CLI
    CLI.from_json(json, program_name)
  end

  @[Deprecated("Use Jargon.cli(program_name, file: path) instead")]
  def self.from_file(path : String, program_name : String = "cli") : CLI
    CLI.from_file(path, program_name)
  end

  # Convenience shortcut with program name first
  def self.cli(program_name : String, *, json : String) : CLI
    CLI.from_json(json, program_name)
  end

  def self.cli(program_name : String, *, file : String) : CLI
    CLI.from_file(file, program_name)
  end

  def self.cli(program_name : String, *, yaml : String) : CLI
    CLI.from_yaml(yaml, program_name)
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

  # Flatten a schema by resolving all $ref pointers and removing $defs.
  # Useful for AI tool definitions that don't support $ref.
  def self.flatten(schema : String) : String
    json = JSON.parse(schema)
    defs = json["$defs"]?.try(&.as_h) || json["definitions"]?.try(&.as_h) || {} of String => JSON::Any
    flattened = flatten_node(json, defs)
    flattened.to_json
  end

  private def self.flatten_node(node : JSON::Any, defs : Hash(String, JSON::Any)) : JSON::Any
    case node.raw
    when Hash
      hash = node.as_h

      # If this node is a $ref, resolve it
      if ref = hash["$ref"]?.try(&.as_s)
        if ref.starts_with?("#/$defs/") || ref.starts_with?("#/definitions/")
          def_name = ref.split("/").last
          if resolved = defs[def_name]?
            return flatten_node(deep_copy(resolved), defs)
          end
        end
        # Keep unresolvable refs as-is
        return node
      end

      # Recursively flatten all values, excluding $defs/definitions
      result = {} of String => JSON::Any
      hash.each do |key, value|
        next if key == "$defs" || key == "definitions"
        result[key] = flatten_node(value, defs)
      end
      JSON::Any.new(result)
    when Array
      JSON::Any.new(node.as_a.map { |item| flatten_node(item, defs) })
    else
      node
    end
  end

  private def self.deep_copy(node : JSON::Any) : JSON::Any
    JSON.parse(node.to_json)
  end
end
