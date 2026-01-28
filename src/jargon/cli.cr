require "yaml"
require "./schema"
require "./result"
require "./config"
require "./help"

module Jargon
  class CLI
    getter schema : Schema?
    getter program_name : String
    getter subcommands : Hash(String, Schema | CLI)
    getter default_subcommand : String?
    getter subcommand_key : String
    property output : IO = STDOUT

    # Create a CLI from a JSON schema string
    def self.from_json(json : String, program_name : String = "cli") : CLI
      schema = Schema.from_json(json)
      CLI.new(schema, program_name)
    end

    # Create a CLI from a JSON schema file
    def self.from_file(path : String, program_name : String = "cli") : CLI
      schema = Schema.from_file(path)
      CLI.new(schema, program_name)
    end

    # Create a CLI from a YAML schema string
    def self.from_yaml(yaml : String, program_name : String = "cli") : CLI
      json = YAML.parse(yaml).to_json
      from_json(json, program_name)
    end

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

    # Parse arguments and return full Result with errors array.
    def parse(args : Array(String) = ARGV, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : Result
      parse(args, STDIN, defaults: defaults)
    end

    def parse(args : Array(String), input : IO, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : Result
      if !@subcommands.empty?
        parse_with_subcommands(args, input, defaults)
      elsif schema = @schema
        parse_flat(args, schema, input, nil, defaults)
      else
        raise ArgumentError.new("CLI has no schema and no subcommands defined")
      end
    end

    # Return just the parsed data as JSON. Raises ParseError on validation errors.
    def json(args : Array(String) = ARGV, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : JSON::Any
      json(args, STDIN, defaults: defaults)
    end

    def json(args : Array(String), input : IO, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : JSON::Any
      result = parse(args, input, defaults: defaults)
      raise ParseError.new(result.errors) unless result.valid?
      result.data
    end

    # Run the CLI with automatic --help, --completions, and error handling.
    # Prints help/completions and exits 0, prints errors and exits 1, otherwise returns/yields result.
    def run(args : Array(String) = ARGV, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : Result
      run(args, STDIN, defaults: defaults)
    end

    def run(args : Array(String) = ARGV, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil, &) : Nil
      run(args, STDIN, defaults: defaults) { |r| yield r }
    end

    def run(args : Array(String), input : IO, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : Result
      result = parse(args, input, defaults: defaults)
      handle_run_result(result)
      result
    end

    def run(args : Array(String), input : IO, *, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil, &) : Nil
      result = parse(args, input, defaults: defaults)
      handle_run_result(result)
      yield result
    end

    private def handle_run_result(result : Result) : Nil
      if result.help_requested?
        if subcmd = result.help_subcommand
          @output.puts help(subcmd)
        else
          @output.puts help
        end
        exit 0
      end

      if result.completion_requested?
        case result.completion_shell
        when "bash" then @output.puts bash_completion
        when "zsh"  then @output.puts zsh_completion
        when "fish" then @output.puts fish_completion
        end
        exit 0
      end

      unless result.valid?
        STDERR.puts result.errors.join("\n")
        exit 1
      end
    end

    private def parse_with_subcommands(args : Array(String), input : IO, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : Result
      # Handle "xerp -" - full JSON with subcommand field
      return parse_from_stdin_full(input, defaults) if args == ["-"]

      # Check for top-level help (--help/-h before any subcommand)
      return Result.new({} of String => JSON::Any, [] of String, nil, true, nil) if help_flag?(args.first?)

      # Check for --completions
      if result = check_completions_flag(args)
        return result
      end

      # Check if first arg matches a known subcommand (supports abbreviations)
      if (first = args.first?) && (resolved_name = resolve_subcommand(first)) && (subcmd = @subcommands[resolved_name]?)
        return dispatch_subcommand(subcmd, resolved_name, args[1..], input, defaults)
      end

      # Fall back to default subcommand if set
      if (default = @default_subcommand) && (subcmd = @subcommands[default]?)
        return dispatch_subcommand(subcmd, default, args, input, defaults)
      end

      # No match and no default
      error = args.empty? ? "No subcommand specified" : "Unknown subcommand: #{args[0]}"
      Result.new({} of String => JSON::Any, [error])
    end

    private def help_flag?(arg : String?) : Bool
      arg == "--help" || arg == "-h"
    end

    private def dispatch_subcommand(subcmd : Schema | CLI, subcmd_name : String, args : Array(String), input : IO, defaults : JSON::Any | Hash(String, JSON::Any) | Nil) : Result
      case subcmd
      when CLI
        result = subcmd.parse(args, input, defaults: defaults)
        full_subcmd = result.subcommand ? "#{subcmd_name} #{result.subcommand}" : subcmd_name
        if result.help_requested?
          help_subcmd = result.help_subcommand ? "#{subcmd_name} #{result.help_subcommand}" : subcmd_name
          return Result.new(result.data, result.errors, full_subcmd, true, help_subcmd)
        end
        Result.new(result.data, result.errors, full_subcmd)
      when Schema
        result = parse_flat(args, subcmd, input, subcmd_name, defaults)
        if result.help_requested?
          return Result.new(result.data, result.errors, subcmd_name, true, subcmd_name)
        end
        Result.new(result.data, result.errors, subcmd_name)
      else
        Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
      end
    end

    private def check_completions_flag(args : Array(String)) : Result?
      return nil unless args.size >= 2 && args[0] == "--completions"
      shell = args[1]
      if shell.in?("bash", "zsh", "fish")
        Result.new({} of String => JSON::Any, [] of String, nil, false, nil, shell)
      else
        Result.new({} of String => JSON::Any, ["Unknown shell '#{shell}'. Supported: bash, zsh, fish"])
      end
    end

    private def parse_from_stdin_full(input : IO, defaults : JSON::Any | Hash(String, JSON::Any) | Nil) : Result
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

      # Resolve abbreviated subcommand name
      resolved_name = resolve_subcommand(subcmd_name)
      unless resolved_name && (subcmd = @subcommands[resolved_name]?)
        return Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
      end
      subcmd_name = resolved_name

      case subcmd
      when CLI
        # For nested CLI, pass remaining JSON to it via stdin simulation
        nested_input = IO::Memory.new(data.to_json)
        result = subcmd.parse(["-"], nested_input, defaults: defaults)
        full_subcmd = result.subcommand ? "#{subcmd_name} #{result.subcommand}" : subcmd_name
        return Result.new(result.data, result.errors, full_subcmd)
      when Schema
        errors = [] of String
        apply_env_vars(data, errors, subcmd)
        apply_user_defaults(data, defaults)
        apply_defaults(data, subcmd)
        validate_data(data, errors, subcmd)
        return Result.new(data, errors, subcmd_name)
      end

      Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
    rescue ex : JSON::ParseException
      Result.new({} of String => JSON::Any, ["Invalid JSON from stdin: #{ex.message}"])
    end

    private def parse_from_stdin_args(input : IO, schema : Schema, defaults : JSON::Any | Hash(String, JSON::Any) | Nil) : Result
      json_str = input.gets_to_end
      json = JSON.parse(json_str)
      data = json.as_h? || {} of String => JSON::Any

      errors = [] of String
      apply_env_vars(data, errors, schema)
      apply_user_defaults(data, defaults)
      apply_defaults(data, schema)
      validate_data(data, errors, schema)

      Result.new(data, errors)
    rescue ex : JSON::ParseException
      Result.new({} of String => JSON::Any, ["Invalid JSON from stdin: #{ex.message}"])
    end

    private def parse_flat(args : Array(String), schema : Schema, input : IO = STDIN, subcommand_path : String? = nil, defaults : JSON::Any | Hash(String, JSON::Any) | Nil = nil) : Result
      # Handle "xerp mark -" - JSON args for this schema
      if args == ["-"]
        return parse_from_stdin_args(input, schema, defaults)
      end

      # Check for help flags early
      help_requested, _ = any_help_requested?(args, schema)
      return Result.new({} of String => JSON::Any, [] of String, nil, true, subcommand_path) if help_requested

      # Check for --completions (only at top level, not within subcommands)
      if subcommand_path.nil? && (result = check_completions_flag(args))
        return result
      end

      data = {} of String => JSON::Any
      errors = [] of String
      positional_names = schema.positional
      positional_index = 0
      short_to_long = build_short_map(schema)
      i = 0

      while i < args.size
        arg = args[i]

        if short_flag?(arg)
          i += handle_short_flag(arg, args, i, data, errors, short_to_long, schema)
        elsif flag?(arg)
          i += handle_long_flag(arg, args, i, data, errors, schema)
        elsif positional_index < positional_names.size
          consumed, pos_advance = handle_positional(arg, args, i, positional_index, positional_names, data, errors, schema)
          i += consumed
          positional_index += pos_advance
        else
          i += handle_extra_arg(arg, args, i, data, errors, schema)
        end
      end

      # Initialize unfilled variadic positionals to empty arrays
      init_empty_variadic(positional_index, positional_names, data, errors, schema)

      # Apply environment variables - CLI args take precedence
      apply_env_vars(data, errors, schema)

      # Apply user-provided defaults (e.g., from config file) - CLI and env vars take precedence
      apply_user_defaults(data, defaults)

      apply_defaults(data, schema)
      validate_data(data, errors, schema)

      Result.new(data, errors)
    end

    private def flag?(arg : String) : Bool
      arg.starts_with?("--")
    end

    private def short_flag?(arg : String) : Bool
      arg.starts_with?("-") && !arg.starts_with?("--") && arg.size > 1
    end

    private def handle_short_flag(arg : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), short_to_long : Hash(String, String), schema : Schema) : Int32
      short_keys = arg[1..]
      if short_keys.size == 1
        handle_single_short_flag(short_keys, args, i, data, errors, short_to_long, schema)
      else
        handle_combined_short_flags(arg, short_keys, data, errors, short_to_long, schema)
        1
      end
    end

    private def handle_single_short_flag(short_keys : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), short_to_long : Hash(String, String), schema : Schema) : Int32
      if long_key = short_to_long[short_keys]?
        key, value, consumed, coerce_error = parse_long_flag("--#{long_key}", args, i, schema)
        if key
          errors << coerce_error if coerce_error
          set_nested_value(data, key, value, errors)
        end
        consumed
      else
        errors << unknown_option_error(short_keys, short_to_long.keys, "-")
        1
      end
    end

    private def handle_combined_short_flags(arg : String, short_keys : String, data : Hash(String, JSON::Any), errors : Array(String), short_to_long : Hash(String, String), schema : Schema) : Nil
      short_keys.each_char do |c|
        char_str = c.to_s
        unless short_to_long[char_str]? && boolean_property?(short_to_long[char_str], schema)
          if !short_to_long[char_str]?
            errors << unknown_option_error(char_str, short_to_long.keys, "-", "in '#{arg}'")
          else
            errors << "Cannot combine non-boolean flag '-#{c}' in '#{arg}'"
          end
          return
        end
      end
      short_keys.each_char do |c|
        long_key = short_to_long[c.to_s]
        set_nested_value(data, long_key, JSON::Any.new(true), errors)
      end
    end

    private def handle_long_flag(arg : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), schema : Schema) : Int32
      key, value, consumed, coerce_error = parse_long_flag(arg, args, i, schema)
      if key
        errors << coerce_error if coerce_error
        set_nested_value(data, key, value, errors)
      else
        opt_name = arg.split("=", 2)[0][2..]
        errors << unknown_option_error(opt_name, available_options(schema))
      end
      consumed
    end

    private def handle_positional(arg : String, args : Array(String), i : Int32, positional_index : Int32, positional_names : Array(String), data : Hash(String, JSON::Any), errors : Array(String), schema : Schema) : {Int32, Int32}
      key = positional_names[positional_index]
      prop = find_property(key, schema)

      if prop.try(&.type) == Property::Type::Array && positional_index == positional_names.size - 1
        consumed = collect_variadic(args, i, key, data, errors)
        {consumed, 1}
      else
        coerced, coerce_error = coerce_value(key, arg, schema)
        errors << coerce_error if coerce_error
        set_nested_value(data, key, coerced, errors)
        {1, 1}
      end
    end

    private def collect_variadic(args : Array(String), start : Int32, key : String, data : Hash(String, JSON::Any), errors : Array(String)) : Int32
      items = [] of JSON::Any
      i = start
      while i < args.size
        current_arg = args[i]
        break if current_arg.starts_with?("-")
        break if current_arg.includes?("=") || current_arg.includes?(":")
        items << JSON::Any.new(current_arg)
        i += 1
      end
      set_nested_value(data, key, JSON::Any.new(items), errors)
      i - start
    end

    private def init_empty_variadic(positional_index : Int32, positional_names : Array(String), data : Hash(String, JSON::Any), errors : Array(String), schema : Schema) : Nil
      return unless positional_index < positional_names.size
      key = positional_names[positional_names.size - 1]
      prop = find_property(key, schema)
      if prop.try(&.type) == Property::Type::Array && !data.has_key?(key)
        set_nested_value(data, key, JSON::Any.new([] of JSON::Any), errors)
      end
    end

    private def handle_extra_arg(arg : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), schema : Schema) : Int32
      key, value, consumed, coerce_error = parse_argument(arg, args, i, schema)
      if key
        errors << coerce_error if coerce_error
        set_nested_value(data, key, value, errors)
      elsif arg.includes?("=") || arg.includes?(":")
        sep = arg.includes?("=") ? "=" : ":"
        unknown_key = arg.split(sep, 2)[0]
        errors << unknown_option_error(unknown_key, available_options(schema), "")
      else
        errors << "Unexpected argument '#{arg}'"
      end
      consumed
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

    private def parse_long_flag(arg : String, args : Array(String), index : Int32, schema : Schema) : {String?, JSON::Any?, Int32, String?}
      key = arg[2..]
      base_key = key.includes?("=") ? key.split("=", 2)[0] : key

      # Validate that the option exists in the schema
      unless property_exists?(base_key, schema)
        return {nil, nil, 1, nil}
      end

      is_boolean = boolean_property?(key, schema)

      if key.includes?("=")
        parts = key.split("=", 2)
        coerced, error = coerce_value(parts[0], parts[1], schema)
        {parts[0], coerced, 1, error}
      elsif is_boolean
        # Check if next arg is a boolean value (--flag true/false)
        if index + 1 < args.size && boolean_value?(args[index + 1])
          coerced, error = coerce_value(key, args[index + 1], schema)
          {key, coerced, 2, error}
        else
          # No value or non-boolean next arg - treat as flag (true)
          {key, JSON::Any.new(true), 1, nil}
        end
      elsif index + 1 < args.size && !flag_like?(args[index + 1])
        # Non-boolean with a value (allows negative numbers)
        coerced, error = coerce_value(key, args[index + 1], schema)
        {key, coerced, 2, error}
      else
        # Non-boolean without a value - error
        {key, nil, 1, "Missing value for --#{key}"}
      end
    end

    # Check if a string is a boolean value
    private def boolean_value?(arg : String) : Bool
      arg.downcase.in?("true", "false", "yes", "no", "on", "off", "1", "0")
    end

    # Check if arg looks like a flag (starts with - but not a negative number)
    private def flag_like?(arg : String) : Bool
      return false unless arg.starts_with?("-")
      return false if arg.size > 1 && arg[1].ascii_number? # -5, -3.14
      true
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

    private def parse_argument(arg : String, args : Array(String), index : Int32, schema : Schema) : {String?, JSON::Any?, Int32, String?}
      # Support key=value and key:value styles
      sep = arg.includes?("=") ? "=" : (arg.includes?(":") ? ":" : nil)
      return {nil, nil, 1, nil} unless sep

      parts = arg.split(sep, 2)
      key = parts[0]
      return {nil, nil, 1, nil} unless property_exists?(key, schema)

      coerced, error = coerce_value(key, parts[1], schema)
      {key, coerced, 1, error}
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

    private def coerce_value(key : String, value : String, schema : Schema) : {JSON::Any, String?}
      prop = find_property(key, schema)

      case prop.try(&.type)
      when Property::Type::Integer
        if int_val = value.to_i64?(strict: true)
          {JSON::Any.new(int_val), nil}
        else
          {JSON::Any.new(value), "Invalid integer value '#{value}' for #{key}"}
        end
      when Property::Type::Number
        if float_val = value.to_f64?(strict: true)
          {JSON::Any.new(float_val), nil}
        else
          {JSON::Any.new(value), "Invalid number value '#{value}' for #{key}"}
        end
      when Property::Type::Boolean
        case value.downcase
        when "true", "1", "yes", "on"  then {JSON::Any.new(true), nil}
        when "false", "0", "no", "off" then {JSON::Any.new(false), nil}
        else                                {JSON::Any.new(value), "Invalid boolean value '#{value}' for #{key}. Use: true/false, yes/no, on/off, 1/0"}
        end
      when Property::Type::Array
        items = value.split(",").map { |v| JSON::Any.new(v.strip) }
        {JSON::Any.new(items), nil}
      else
        {JSON::Any.new(value), nil}
      end
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

    private def apply_env_vars(data : Hash(String, JSON::Any), errors : Array(String), schema : Schema)
      root = resolve_property(schema.root, schema)
      return unless props = root.properties

      props.each do |name, prop|
        resolved_prop = resolve_property(prop, schema)
        next if data.has_key?(name) # CLI arg takes precedence
        next unless env_var = resolved_prop.env
        next unless env_value = ENV[env_var]?

        coerced, coerce_error = coerce_value(name, env_value, schema)
        errors << coerce_error if coerce_error
        data[name] = coerced
      end
    end

    private def apply_user_defaults(data : Hash(String, JSON::Any), defaults : JSON::Any | Hash(String, JSON::Any) | Nil)
      return unless defaults
      default_hash = defaults.is_a?(JSON::Any) ? defaults.as_h : defaults
      default_hash.each do |key, value|
        data[key] = value unless data.has_key?(key)
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

      if prop.required? && value.nil?
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

    # Find best suggestion for a typo using Levenshtein distance
    # Returns nil if no good match found (distance > 2 or > 30% of length)
    private def find_suggestion(input : String, candidates : Array(String)) : String?
      return nil if candidates.empty?
      return nil if input.size < 2 # Don't suggest for single-character inputs

      best_match : String? = nil
      best_distance = Int32::MAX

      candidates.each do |candidate|
        distance = levenshtein_distance(input, candidate)
        max_len = Math.max(input.size, candidate.size)
        max_allowed = (max_len * 0.3).to_i

        if distance <= 2 && distance <= max_allowed && distance < best_distance
          best_distance = distance
          best_match = candidate
        end
      end

      best_match
    end

    # Generate error message for unknown option with suggestion support
    private def unknown_option_error(input : String, candidates : Array(String), prefix : String = "--", context : String? = nil) : String
      display = "#{prefix}#{input}"
      ctx = context ? " #{context}" : ""

      if candidates.empty?
        "Unknown option '#{display}'#{ctx}: no #{prefix == "-" ? "short flags" : "options"} defined"
      elsif suggestion = find_suggestion(input, candidates)
        "Unknown option '#{display}'#{ctx}. Did you mean '#{prefix}#{suggestion}'?"
      else
        formatted = candidates.map { |c| "#{prefix}#{c}" }.join(", ")
        "Unknown option '#{display}'#{ctx}. Available: #{formatted}"
      end
    end

    # Levenshtein distance between two strings
    private def levenshtein_distance(s1 : String, s2 : String) : Int32
      return s2.size if s1.empty?
      return s1.size if s2.empty?

      # Use two-row optimization for space efficiency
      prev_row = Array.new(s2.size + 1) { |i| i }
      curr_row = Array.new(s2.size + 1, 0)

      s1.each_char.with_index do |c1, i|
        curr_row[0] = i + 1

        s2.each_char.with_index do |c2, j|
          cost = c1 == c2 ? 0 : 1
          curr_row[j + 1] = Math.min(
            curr_row[j] + 1, # insertion
            Math.min(
            prev_row[j + 1] + 1, # deletion
            prev_row[j] + cost   # substitution
          )
          )
        end

        prev_row, curr_row = curr_row, prev_row
      end

      prev_row[s2.size]
    end

    # Resolve abbreviated subcommand name to full name
    # Returns nil if no match, ambiguous, or too short (< 3 chars for non-exact)
    private def resolve_subcommand(input : String) : String?
      return input if @subcommands.has_key?(input) # Exact match
      return nil if input.size < 3                 # Too short for abbreviation

      matches = @subcommands.keys.select(&.starts_with?(input))
      matches.size == 1 ? matches.first : nil # Unambiguous only
    end
  end
end
