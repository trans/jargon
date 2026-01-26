require "./schema"
require "./result"

module Jargon
  class CLI
    getter schema : Schema?
    getter program_name : String
    getter subcommands : Hash(String, Schema | CLI)
    getter default_subcommand : String?
    getter subcommand_key : String

    def initialize(@schema : Schema, @program_name : String = "cli")
      @subcommands = {} of String => Schema | CLI
      @default_subcommand = nil
      @subcommand_key = "subcommand"
    end

    def initialize(@program_name : String)
      @schema = nil
      @subcommands = {} of String => Schema | CLI
      @default_subcommand = nil
      @subcommand_key = "subcommand"
    end

    def subcommand(name : String, schema : Schema | String)
      @subcommands[name] = case schema
      when String then Schema.from_json(schema)
      else             schema
      end
    end

    def subcommand(name : String, cli : CLI)
      @subcommands[name] = cli
    end

    def default_subcommand(name : String)
      @default_subcommand = name
    end

    def subcommand_key(key : String)
      @subcommand_key = key
    end

    def parse(args : Array(String)) : Result
      parse(args, STDIN)
    end

    def parse(args : Array(String), input : IO) : Result
      if @subcommands.any?
        parse_with_subcommands(args, input)
      else
        parse_flat(args, @schema.not_nil!, input)
      end
    end

    private def parse_with_subcommands(args : Array(String), input : IO) : Result
      # Handle "xerp -" - full JSON with subcommand field
      if args == ["-"]
        return parse_from_stdin_full(input)
      end

      # Check for top-level help (--help/-h before any subcommand)
      if args.any? && (args[0] == "--help" || args[0] == "-h")
        return Result.new({} of String => JSON::Any, [] of String, nil, true, nil)
      end

      # Check if first arg matches a known subcommand
      if args.any? && (subcmd = @subcommands[args[0]]?)
        subcmd_name = args[0]
        case subcmd
        when CLI
          result = subcmd.parse(args[1..], input)
          # Prepend parent subcommand name
          full_subcmd = result.subcommand ? "#{subcmd_name} #{result.subcommand}" : subcmd_name
          if result.help_requested?
            # Propagate help with updated subcommand path
            help_subcmd = result.help_subcommand ? "#{subcmd_name} #{result.help_subcommand}" : subcmd_name
            return Result.new(result.data, result.errors, full_subcmd, true, help_subcmd)
          end
          return Result.new(result.data, result.errors, full_subcmd)
        when Schema
          result = parse_flat(args[1..], subcmd, input, subcmd_name)
          if result.help_requested?
            return Result.new(result.data, result.errors, subcmd_name, true, subcmd_name)
          end
          return Result.new(result.data, result.errors, subcmd_name)
        end
      end

      # Fall back to default subcommand if set
      if default = @default_subcommand
        if subcmd = @subcommands[default]?
          case subcmd
          when CLI
            result = subcmd.parse(args, input)
            full_subcmd = result.subcommand ? "#{default} #{result.subcommand}" : default
            if result.help_requested?
              help_subcmd = result.help_subcommand ? "#{default} #{result.help_subcommand}" : default
              return Result.new(result.data, result.errors, full_subcmd, true, help_subcmd)
            end
            return Result.new(result.data, result.errors, full_subcmd)
          when Schema
            result = parse_flat(args, subcmd, input, default)
            if result.help_requested?
              return Result.new(result.data, result.errors, default, true, default)
            end
            return Result.new(result.data, result.errors, default)
          end
        end
      end

      # No match and no default
      if args.empty?
        Result.new({} of String => JSON::Any, ["No subcommand specified"])
      else
        Result.new({} of String => JSON::Any, ["Unknown subcommand: #{args[0]}"])
      end
    end

    private def parse_from_stdin_full(input : IO) : Result
      json_str = input.gets_to_end
      json = JSON.parse(json_str)
      data = json.as_h? || {} of String => JSON::Any

      # Extract subcommand from JSON using configured key
      subcmd_name = data.delete(@subcommand_key).try(&.as_s?)

      # Determine which subcommand to use
      subcmd_name ||= @default_subcommand

      unless subcmd_name
        return Result.new({} of String => JSON::Any, ["No '#{@subcommand_key}' specified in JSON"])
      end

      unless subcmd = @subcommands[subcmd_name]?
        return Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
      end

      case subcmd
      when CLI
        # For nested CLI, pass remaining JSON to it via stdin simulation
        nested_input = IO::Memory.new(data.to_json)
        result = subcmd.parse(["-"], nested_input)
        full_subcmd = result.subcommand ? "#{subcmd_name} #{result.subcommand}" : subcmd_name
        return Result.new(result.data, result.errors, full_subcmd)
      when Schema
        errors = [] of String
        apply_defaults(data, subcmd)
        validate_data(data, errors, subcmd)
        return Result.new(data, errors, subcmd_name)
      end

      Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
    rescue ex : JSON::ParseException
      Result.new({} of String => JSON::Any, ["Invalid JSON from stdin: #{ex.message}"])
    end

    private def parse_from_stdin_args(input : IO, schema : Schema) : Result
      json_str = input.gets_to_end
      json = JSON.parse(json_str)
      data = json.as_h? || {} of String => JSON::Any

      errors = [] of String
      apply_defaults(data, schema)
      validate_data(data, errors, schema)

      Result.new(data, errors)
    rescue ex : JSON::ParseException
      Result.new({} of String => JSON::Any, ["Invalid JSON from stdin: #{ex.message}"])
    end

    private def parse_flat(args : Array(String), schema : Schema, input : IO = STDIN, subcommand_path : String? = nil) : Result
      # Handle "xerp mark -" - JSON args for this schema
      if args == ["-"]
        return parse_from_stdin_args(input, schema)
      end

      # Check for help flags early
      help_requested, _ = any_help_requested?(args, schema)
      if help_requested
        return Result.new({} of String => JSON::Any, [] of String, nil, true, subcommand_path)
      end

      data = {} of String => JSON::Any
      errors = [] of String
      positional_names = schema.positional
      positional_index = 0
      short_to_long = build_short_map(schema)
      i = 0

      while i < args.size
        arg = args[i]

        if is_short_flag?(arg)
          short_key = arg[1..]
          if long_key = short_to_long[short_key]?
            key, value, consumed = parse_long_flag("--#{long_key}", args, i, schema)
            if key
              set_nested_value(data, key, value, errors)
            end
            i += consumed
          else
            available_shorts = short_to_long.keys.map { |s| "-#{s}" }
            if available_shorts.empty?
              errors << "Unknown option '#{arg}': no short flags defined"
            else
              errors << "Unknown option '#{arg}'. Available short flags: #{available_shorts.join(", ")}"
            end
            i += 1
          end
        elsif is_flag?(arg)
          key, value, consumed = parse_long_flag(arg, args, i, schema)
          if key
            set_nested_value(data, key, value, errors)
          else
            opt_name = arg[2..]
            opts = available_options(schema)
            if opts.empty?
              errors << "Unknown option '#{arg}': no options defined"
            else
              errors << "Unknown option '#{arg}'. Available options: #{opts.map { |o| "--#{o}" }.join(", ")}"
            end
          end
          i += consumed
        elsif positional_index < positional_names.size
          key = positional_names[positional_index]
          set_nested_value(data, key, coerce_value(key, arg, schema), errors)
          positional_index += 1
          i += 1
        else
          key, value, consumed = parse_argument(arg, args, i, schema)
          if key
            set_nested_value(data, key, value, errors)
          else
            # Determine if this looks like a key=value or key:value with unknown key
            if arg.includes?("=") || arg.includes?(":")
              sep = arg.includes?("=") ? "=" : ":"
              unknown_key = arg.split(sep, 2)[0]
              opts = available_options(schema)
              if opts.empty?
                errors << "Unknown option '#{unknown_key}': no options defined"
              else
                errors << "Unknown option '#{unknown_key}'. Available options: #{opts.join(", ")}"
              end
            else
              errors << "Unexpected argument '#{arg}'"
            end
          end
          i += consumed
        end
      end

      apply_defaults(data, schema)
      validate_data(data, errors, schema)

      Result.new(data, errors)
    end

    private def is_flag?(arg : String) : Bool
      arg.starts_with?("--")
    end

    private def is_short_flag?(arg : String) : Bool
      arg.starts_with?("-") && !arg.starts_with?("--") && arg.size > 1
    end

    private def build_short_map(schema : Schema) : Hash(String, String)
      map = {} of String => String
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.each do |name, prop|
          if short = prop.short
            map[short] = name
          end
        end
      end
      map
    end

    private def parse_long_flag(arg : String, args : Array(String), index : Int32, schema : Schema) : {String?, JSON::Any?, Int32}
      key = arg[2..]
      base_key = key.includes?("=") ? key.split("=", 2)[0] : key

      # Validate that the option exists in the schema
      unless property_exists?(base_key, schema)
        return {nil, nil, 1}
      end

      if key.includes?("=")
        parts = key.split("=", 2)
        {parts[0], coerce_value(parts[0], parts[1], schema), 1}
      elsif index + 1 < args.size && !args[index + 1].starts_with?("-")
        if boolean_property?(key, schema)
          {key, JSON::Any.new(true), 1}
        else
          {key, coerce_value(key, args[index + 1], schema), 2}
        end
      else
        {key, JSON::Any.new(true), 1}
      end
    end

    def help : String
      if @subcommands.any?
        help_with_subcommands
      elsif s = @schema
        help_flat(s)
      else
        "Usage: #{program_name} <command> [options]"
      end
    end

    def help(subcommand : String) : String
      parts = subcommand.split(" ", 2)
      subcmd_name = parts[0]

      unless subcmd = @subcommands[subcmd_name]?
        return "Unknown subcommand: #{subcmd_name}"
      end

      case subcmd
      when CLI
        if parts.size > 1
          subcmd.help(parts[1])
        else
          subcmd.help
        end
      when Schema
        help_flat_for_subcommand(subcmd, subcmd_name)
      else
        "Unknown subcommand: #{subcmd_name}"
      end
    end

    # Validate data against a schema, returning any errors.
    # If no schema is provided, uses the CLI's root schema.
    # For subcommand validation, pass the subcommand name (space-separated for nested).
    def validate(data : Hash(String, JSON::Any), subcommand : String? = nil) : Array(String)
      errors = [] of String
      if cmd = subcommand
        parts = cmd.split(" ", 2)
        subcmd = @subcommands[parts[0]]? || raise ArgumentError.new("Unknown subcommand: #{parts[0]}")
        case subcmd
        when CLI
          # Delegate to nested CLI with remaining subcommand path
          return subcmd.validate(data, parts[1]?)
        when Schema
          validate_data(data, errors, subcmd)
        end
      else
        schema = @schema || raise ArgumentError.new("No schema available")
        validate_data(data, errors, schema)
      end
      errors
    end

    def validate(result : Result) : Array(String)
      validate(result.data.as_h, result.subcommand)
    end

    def bash_completion : String
      Completion.new(self).bash
    end

    def zsh_completion : String
      Completion.new(self).zsh
    end

    def fish_completion : String
      Completion.new(self).fish
    end

    private def help_with_subcommands : String
      lines = ["Usage: #{program_name} <command> [options]", "", "Commands:"]
      @subcommands.each do |name, subcmd|
        case subcmd
        when CLI
          lines << "  #{name}"
          subcmd.subcommands.each_key do |sub_name|
            lines << "    #{sub_name}"
          end
        else
          lines << "  #{name}"
        end
      end
      lines << ""
      lines << "Run '#{program_name} <command> --help' for command-specific options."
      lines.join("\n")
    end

    private def user_defined_help?(schema : Schema) : Bool
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.has_key?("help")
      else
        false
      end
    end

    private def user_defined_h_short?(schema : Schema) : Bool
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.values.any? { |prop| prop.short == "h" }
      else
        false
      end
    end

    private def any_help_requested?(args : Array(String), schema : Schema?) : {Bool, Int32}
      args.each_with_index do |arg, i|
        if arg == "--help"
          if schema && user_defined_help?(schema)
            return {false, -1}
          end
          return {true, i}
        elsif arg == "-h"
          if schema && user_defined_h_short?(schema)
            return {false, -1}
          end
          return {true, i}
        end
      end
      {false, -1}
    end

    private def help_flat_for_subcommand(schema : Schema, subcmd_name : String) : String
      lines = [] of String
      positional_names = schema.positional
      root = resolve_property(schema.root, schema)

      # Build usage line with subcommand name
      usage_parts = ["Usage: #{program_name} #{subcmd_name}"]
      positional_names.each do |name|
        if prop = root.properties.try(&.[name]?)
          if prop.required
            usage_parts << "<#{name}>"
          else
            usage_parts << "[#{name}]"
          end
        else
          usage_parts << "<#{name}>"
        end
      end
      usage_parts << "[options]"
      lines << usage_parts.join(" ")
      lines << ""

      # Arguments section
      unless positional_names.empty?
        lines << "Arguments:"
        positional_names.each do |name|
          if prop = root.properties.try(&.[name]?)
            desc = prop.description || ""
            lines << "  #{name}    #{desc}"
          end
        end
        lines << ""
      end

      # Options section
      lines << "Options:"
      if props = root.properties
        props.each do |name, prop|
          next if positional_names.includes?(name)
          build_help_lines(lines, name, resolve_property(prop, schema), "", schema)
        end
      end

      lines.join("\n")
    end

    private def help_flat(schema : Schema) : String
      lines = [] of String
      positional_names = schema.positional
      root = resolve_property(schema.root, schema)

      # Build usage line
      usage_parts = ["Usage: #{program_name}"]
      positional_names.each do |name|
        if prop = root.properties.try(&.[name]?)
          if prop.required
            usage_parts << "<#{name}>"
          else
            usage_parts << "[#{name}]"
          end
        else
          usage_parts << "<#{name}>"
        end
      end
      usage_parts << "[options]"
      lines << usage_parts.join(" ")
      lines << ""

      # Arguments section
      unless positional_names.empty?
        lines << "Arguments:"
        positional_names.each do |name|
          if prop = root.properties.try(&.[name]?)
            desc = prop.description || ""
            lines << "  #{name}    #{desc}"
          end
        end
        lines << ""
      end

      # Options section
      lines << "Options:"
      if props = root.properties
        props.each do |name, prop|
          next if positional_names.includes?(name)
          build_help_lines(lines, name, resolve_property(prop, schema), "", schema)
        end
      end

      lines.join("\n")
    end

    private def parse_argument(arg : String, args : Array(String), index : Int32, schema : Schema) : {String?, JSON::Any?, Int32}
      # Style 1: key=value
      if arg.includes?("=")
        parts = arg.split("=", 2)
        key = parts[0]
        unless property_exists?(key, schema)
          return {nil, nil, 1}
        end
        {key, coerce_value(key, parts[1], schema), 1}
      # Style 2: key:value
      elsif arg.includes?(":")
        parts = arg.split(":", 2)
        key = parts[0]
        unless property_exists?(key, schema)
          return {nil, nil, 1}
        end
        {key, coerce_value(key, parts[1], schema), 1}
      else
        {nil, nil, 1}
      end
    end

    private def boolean_property?(key : String, schema : Schema) : Bool
      prop = find_property(key, schema)
      prop.try(&.type.boolean?) || false
    end

    private def property_exists?(key : String, schema : Schema) : Bool
      !find_property(key, schema).nil?
    end

    private def available_options(schema : Schema) : Array(String)
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.keys
      else
        [] of String
      end
    end

    private def find_property(key : String, schema : Schema) : Property?
      parts = key.split(".")
      current = resolve_property(schema.root, schema)

      parts.each_with_index do |part, i|
        if props = current.properties
          if prop = props[part]?
            resolved = resolve_property(prop, schema)
            if i == parts.size - 1
              return resolved
            elsif resolved.type.object?
              current = resolved
            else
              return nil
            end
          else
            return nil
          end
        else
          return nil
        end
      end

      nil
    end

    private def resolve_property(prop : Property, schema : Schema) : Property
      if ref = prop.ref
        schema.resolve_ref(ref) || prop
      else
        prop
      end
    end

    private def coerce_value(key : String, value : String, schema : Schema) : JSON::Any
      prop = find_property(key, schema)

      case prop.try(&.type)
      when Property::Type::Integer
        JSON::Any.new(value.to_i64)
      when Property::Type::Number
        JSON::Any.new(value.to_f64)
      when Property::Type::Boolean
        JSON::Any.new(value.downcase.in?("true", "1", "yes", "on"))
      when Property::Type::Array
        items = value.split(",").map { |v| JSON::Any.new(v.strip) }
        JSON::Any.new(items)
      else
        JSON::Any.new(value)
      end
    rescue
      JSON::Any.new(value)
    end

    private def set_nested_value(data : Hash(String, JSON::Any), key : String, value : JSON::Any?, errors : Array(String))
      return unless value

      parts = key.split(".")

      if parts.size == 1
        data[key] = value
      else
        current = data
        parts[0..-2].each do |part|
          unless current[part]?
            current[part] = JSON::Any.new({} of String => JSON::Any)
          end
          if current[part].as_h?
            current = current[part].as_h
          else
            errors << "Cannot set nested property #{key}: #{part} is not an object"
            return
          end
        end
        current[parts.last] = value
      end
    end

    private def apply_defaults(data : Hash(String, JSON::Any), schema : Schema)
      root = resolve_property(schema.root, schema)
      return unless props = root.properties

      props.each do |name, prop|
        apply_property_defaults(data, name, resolve_property(prop, schema), schema)
      end
    end

    private def apply_property_defaults(data : Hash(String, JSON::Any), name : String, prop : Property, schema : Schema)
      unless data.has_key?(name)
        if default = prop.default
          data[name] = default
        end
      end

      if prop.type.object? && (nested_props = prop.properties)
        if nested_data = data[name]?.try(&.as_h?)
          nested_props.each do |nested_name, nested_prop|
            apply_property_defaults(nested_data, nested_name, resolve_property(nested_prop, schema), schema)
          end
        end
      end
    end

    private def validate_data(data : Hash(String, JSON::Any), errors : Array(String), schema : Schema)
      root = resolve_property(schema.root, schema)
      return unless props = root.properties

      props.each do |name, prop|
        validate_property(data, name, resolve_property(prop, schema), errors, "", schema)
      end
    end

    private def validate_property(data : Hash(String, JSON::Any), name : String, prop : Property, errors : Array(String), prefix : String, schema : Schema)
      full_name = prefix.empty? ? name : "#{prefix}.#{name}"
      value = data[name]?

      if prop.required && value.nil?
        errors << "Missing required field: #{full_name}"
        return
      end

      return unless value

      # Type validation
      unless valid_type?(value, prop.type)
        errors << "Invalid type for #{full_name}: expected #{prop.type}, got #{value.raw.class}"
      end

      # Enum validation
      if enum_values = prop.enum_values
        unless enum_values.includes?(value)
          errors << "Invalid value for #{full_name}: must be one of #{enum_values.map(&.inspect).join(", ")}"
        end
      end

      # Nested object validation
      if prop.type.object? && (nested_props = prop.properties)
        if nested_data = value.as_h?
          nested_props.each do |nested_name, nested_prop|
            validate_property(nested_data, nested_name, resolve_property(nested_prop, schema), errors, full_name, schema)
          end
        end
      end
    end

    private def valid_type?(value : JSON::Any, expected : Property::Type) : Bool
      case expected
      when Property::Type::String  then value.as_s? != nil
      when Property::Type::Integer then value.as_i64? != nil
      when Property::Type::Number  then value.as_f? != nil || value.as_i64? != nil
      when Property::Type::Boolean then value.as_bool? != nil
      when Property::Type::Array   then value.as_a? != nil
      when Property::Type::Object  then value.as_h? != nil
      when Property::Type::Null    then value.raw.nil?
      else                              true
      end
    end

    private def build_help_lines(lines : Array(String), name : String, prop : Property, prefix : String, schema : Schema)
      full_name = prefix.empty? ? name : "#{prefix}.#{name}"
      type_str = prop.type.to_s.downcase
      required_str = prop.required ? " (required)" : ""
      default_str = prop.default ? " [default: #{prop.default}]" : ""
      desc = prop.description || ""

      flag_str = if short = prop.short
        "-#{short}, --#{full_name}"
      else
        "    --#{full_name}"
      end

      if prop.type.boolean?
        lines << "  #{flag_str}#{required_str}#{default_str}"
      else
        lines << "  #{flag_str}=<#{type_str}>#{required_str}#{default_str}"
      end
      lines << "      #{desc}" unless desc.empty?

      if prop.type.object? && (nested_props = prop.properties)
        nested_props.each do |nested_name, nested_prop|
          build_help_lines(lines, nested_name, resolve_property(nested_prop, schema), full_name, schema)
        end
      end
    end
  end
end
