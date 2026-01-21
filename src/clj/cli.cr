require "./schema"
require "./result"

module CLJ
  class CLI
    getter schema : Schema
    getter program_name : String

    def initialize(@schema : Schema, @program_name : String = "cli")
    end

    def parse(args : Array(String)) : Result
      data = {} of String => JSON::Any
      errors = [] of String
      i = 0

      while i < args.size
        arg = args[i]
        key, value, consumed = parse_argument(arg, args, i)

        if key
          set_nested_value(data, key, value, errors)
        else
          errors << "Unknown argument: #{arg}"
        end

        i += consumed
      end

      apply_defaults(data)
      validate(data, errors)

      Result.new(data, errors)
    end

    def help : String
      lines = ["Usage: #{program_name} [OPTIONS]", "", "Options:"]

      root = resolve_property(schema.root)
      if props = root.properties
        props.each do |name, prop|
          build_help_lines(lines, name, resolve_property(prop), "")
        end
      end

      lines.join("\n")
    end

    private def parse_argument(arg : String, args : Array(String), index : Int32) : {String?, JSON::Any?, Int32}
      # Style 1: Traditional --key value or --key=value
      if arg.starts_with?("--")
        key = arg[2..]
        if key.includes?("=")
          parts = key.split("=", 2)
          {parts[0], coerce_value(parts[0], parts[1]), 1}
        elsif index + 1 < args.size && !args[index + 1].starts_with?("-")
          # Check if this is a boolean flag (no value needed)
          if boolean_property?(key)
            {key, JSON::Any.new(true), 1}
          else
            {key, coerce_value(key, args[index + 1]), 2}
          end
        else
          # Boolean flag
          {key, JSON::Any.new(true), 1}
        end
      # Style 2: key=value
      elsif arg.includes?("=")
        parts = arg.split("=", 2)
        {parts[0], coerce_value(parts[0], parts[1]), 1}
      # Style 3: key:value
      elsif arg.includes?(":")
        parts = arg.split(":", 2)
        {parts[0], coerce_value(parts[0], parts[1]), 1}
      else
        {nil, nil, 1}
      end
    end

    private def boolean_property?(key : String) : Bool
      prop = find_property(key)
      prop.try(&.type.boolean?) || false
    end

    private def find_property(key : String) : Property?
      parts = key.split(".")
      current = resolve_property(schema.root)

      parts.each_with_index do |part, i|
        if props = current.properties
          if prop = props[part]?
            resolved = resolve_property(prop)
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

    private def resolve_property(prop : Property) : Property
      if ref = prop.ref
        schema.resolve_ref(ref) || prop
      else
        prop
      end
    end

    private def coerce_value(key : String, value : String) : JSON::Any
      prop = find_property(key)

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

    private def apply_defaults(data : Hash(String, JSON::Any))
      root = resolve_property(schema.root)
      return unless props = root.properties

      props.each do |name, prop|
        apply_property_defaults(data, name, resolve_property(prop))
      end
    end

    private def apply_property_defaults(data : Hash(String, JSON::Any), name : String, prop : Property)
      unless data.has_key?(name)
        if default = prop.default
          data[name] = default
        end
      end

      if prop.type.object? && (nested_props = prop.properties)
        if nested_data = data[name]?.try(&.as_h?)
          nested_props.each do |nested_name, nested_prop|
            apply_property_defaults(nested_data, nested_name, resolve_property(nested_prop))
          end
        end
      end
    end

    private def validate(data : Hash(String, JSON::Any), errors : Array(String))
      root = resolve_property(schema.root)
      return unless props = root.properties

      props.each do |name, prop|
        validate_property(data, name, resolve_property(prop), errors, "")
      end
    end

    private def validate_property(data : Hash(String, JSON::Any), name : String, prop : Property, errors : Array(String), prefix : String)
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
            validate_property(nested_data, nested_name, resolve_property(nested_prop), errors, full_name)
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

    private def build_help_lines(lines : Array(String), name : String, prop : Property, prefix : String)
      full_name = prefix.empty? ? name : "#{prefix}.#{name}"
      type_str = prop.type.to_s.downcase
      required_str = prop.required ? " (required)" : ""
      default_str = prop.default ? " [default: #{prop.default}]" : ""
      desc = prop.description || ""

      lines << "  --#{full_name}=<#{type_str}>#{required_str}#{default_str}"
      lines << "      #{desc}" unless desc.empty?

      if prop.type.object? && (nested_props = prop.properties)
        nested_props.each do |nested_name, nested_prop|
          build_help_lines(lines, nested_name, resolve_property(nested_prop), full_name)
        end
      end
    end
  end
end
