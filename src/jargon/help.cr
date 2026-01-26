module Jargon
  class CLI
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
