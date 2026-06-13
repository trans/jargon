require "json"
require "./schema"

module Jargon
  module Validator
    # Validate data against a schema. Returns an array of error strings (empty if valid).
    def self.validate(data : Hash(String, JSON::Any), schema : Schema) : Array(String)
      errors = [] of String
      root = resolve_property(schema.root, schema)
      return errors unless props = root.properties

      # additionalProperties check at root level
      check_additional_properties(data, root, errors, "", props)

      props.each do |name, prop|
        validate_property(data, name, resolve_property(prop, schema), errors, "", schema)
      end

      errors
    end

    private def self.validate_property(data : Hash(String, JSON::Any), name : String, prop : Property, errors : Array(String), prefix : String, schema : Schema)
      full_name = prefix.empty? ? name : "#{prefix}.#{name}"
      value = data[name]?

      if prop.required? && value.nil?
        errors << "Missing required field: #{full_name}"
        return
      end

      return unless value

      validate_type_match(value, prop, errors, full_name)
      validate_const(value, prop, errors, full_name)
      validate_enum(value, prop, errors, full_name)
      validate_numeric(value, prop, errors, full_name)
      validate_string(value, prop, errors, full_name)
      validate_array(value, prop, errors, full_name, schema)
      validate_object(value, prop, errors, full_name, schema)
    end

    private def self.validate_array_item(value : JSON::Any, prop : Property, errors : Array(String), item_name : String)
      validate_type_match(value, prop, errors, item_name)
      validate_enum(value, prop, errors, item_name)
      validate_numeric(value, prop, errors, item_name)
      validate_string(value, prop, errors, item_name)
    end

    private def self.validate_type_match(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      unless valid_type?(value, prop.type)
        errors << "Invalid type for #{label}: expected #{prop.type}, got #{value.raw.class}"
      end
    end

    private def self.validate_const(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless const_val = prop.const
      unless value == const_val
        errors << "Value for #{label} must be #{const_val.as_s? || const_val.to_json}"
      end
    end

    private def self.validate_enum(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless enum_values = prop.enum_values
      unless enum_values.includes?(value)
        formatted = enum_values.map { |v| v.as_s? || v.to_json }.join(", ")
        errors << "Invalid value for #{label}: must be one of #{formatted}"
      end
    end

    private def self.validate_array(value : JSON::Any, prop : Property, errors : Array(String), label : String, schema : Schema)
      return unless prop.type.array?
      return unless arr = value.as_a?

      if min = prop.min_items
        errors << "#{label} must have at least #{min} items" if arr.size < min
      end
      if max = prop.max_items
        errors << "#{label} must have at most #{max} items" if arr.size > max
      end
      validate_unique_items(arr, prop, errors, label)

      if items_prop = prop.items
        arr.each_with_index do |item, i|
          validate_array_item(item, items_prop, errors, "#{label}[#{i}]")
        end
      end
    end

    private def self.validate_unique_items(arr : Array(JSON::Any), prop : Property, errors : Array(String), label : String)
      return unless prop.unique_items?

      seen = Set(String).new
      arr.each do |item|
        key = item.to_json
        if seen.includes?(key)
          errors << "#{label} must have unique items (duplicate: #{item.as_s? || item.to_json})"
          break
        end
        seen << key
      end
    end

    private def self.validate_object(value : JSON::Any, prop : Property, errors : Array(String), label : String, schema : Schema)
      return unless prop.type.object? && (nested_props = prop.properties)
      return unless nested_data = value.as_h?

      check_additional_properties(nested_data, prop, errors, label, nested_props)
      nested_props.each do |nested_name, nested_prop|
        validate_property(nested_data, nested_name, resolve_property(nested_prop, schema), errors, label, schema)
      end
    end

    # Shared numeric-constraint checks. `label` is the field or item path used
    # in error messages.
    private def self.validate_numeric(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless prop.type.integer? || prop.type.number?
      return unless num = value.as_f? || value.as_i64?.try(&.to_f)

      validate_range(num, prop, errors, label)
      validate_multiple_of(num, prop, errors, label)
    end

    private def self.validate_range(num : Float64, prop : Property, errors : Array(String), label : String)
      if min = prop.minimum
        errors << "Value for #{label} must be >= #{format_num(min)}" if num < min
      end
      if max = prop.maximum
        errors << "Value for #{label} must be <= #{format_num(max)}" if num > max
      end
      if min = prop.exclusive_minimum
        errors << "Value for #{label} must be > #{format_num(min)}" if num <= min
      end
      if max = prop.exclusive_maximum
        errors << "Value for #{label} must be < #{format_num(max)}" if num >= max
      end
    end

    private def self.validate_multiple_of(num : Float64, prop : Property, errors : Array(String), label : String)
      return unless mult = prop.multiple_of
      unless (num % mult).abs < 1e-10
        errors << "Value for #{label} must be a multiple of #{format_num(mult)}"
      end
    end

    # Shared string-constraint checks (minLength/maxLength/pattern/format).
    # `label` is the field or item path used in error messages.
    private def self.validate_string(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless prop.type.string?
      return unless str = value.as_s?

      if min = prop.min_length
        errors << "Value for #{label} must be at least #{min} characters" if str.size < min
      end
      if max = prop.max_length
        errors << "Value for #{label} must be at most #{max} characters" if str.size > max
      end
      if pattern = prop.pattern
        errors << "Value for #{label} must match pattern: #{pattern.source}" unless pattern.matches?(str)
      end
      if fmt = prop.format
        unless valid_format?(str, fmt)
          errors << "Value for #{label} must be a valid #{fmt}"
        end
      end
    end

    private def self.check_additional_properties(data : Hash(String, JSON::Any), prop : Property, errors : Array(String), prefix : String, known_props : Hash(String, Property))
      return unless prop.additional_properties == false

      known_keys = known_props.keys.to_set
      data.each_key do |key|
        unless known_keys.includes?(key)
          full_name = prefix.empty? ? key : "#{prefix}.#{key}"
          errors << "Unknown property '#{full_name}': additionalProperties is false"
        end
      end
    end

    private def self.format_num(n : Float64) : String
      n.to_i == n ? n.to_i.to_s : n.to_s
    end

    private def self.valid_format?(value : String, format : String) : Bool
      case format
      when "email"
        value.matches?(/^[^@\s]+@[^@\s]+\.[^@\s]+$/)
      when "uri", "url"
        value.matches?(/^[a-z][a-z0-9+.-]*:\/\/.+$/i)
      when "uuid"
        value.matches?(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
      when "date"
        value.matches?(/^\d{4}-\d{2}-\d{2}$/)
      when "time"
        value.matches?(/^\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})?$/)
      when "date-time"
        value.matches?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})?$/)
      when "ipv4"
        parts = value.split(".")
        parts.size == 4 && parts.all? { |p| p.to_i?.try { |n| n >= 0 && n <= 255 } || false }
      when "ipv6"
        value.matches?(/^([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}$/i)
      when "hostname"
        value.matches?(/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/i)
      when "path"
        true # Any string is a valid path; expansion happens at the CLI layer
      else
        true # Unknown formats pass (per JSON Schema spec)
      end
    end

    private def self.valid_type?(value : JSON::Any, expected : Property::Type) : Bool
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

    private def self.resolve_property(prop : Property, schema : Schema) : Property
      if ref = prop.ref
        schema.resolve_ref(ref) || prop
      else
        prop
      end
    end
  end
end
