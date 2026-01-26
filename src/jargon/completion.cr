module Jargon
  # Information about a flag for completion generation
  record FlagInfo, long : String, short : String?, description : String?, enum_values : Array(String)?

  # Information about a subcommand for completion generation
  record SubcommandInfo, name : String, description : String?, schema : Schema?

  class Completion
    def initialize(@cli : CLI)
    end

    def bash : String
      program = @cli.program_name
      func_name = "_#{program.gsub("-", "_")}_completions"

      lines = [] of String
      lines << "#{func_name}() {"
      lines << "    local cur=\"${COMP_WORDS[COMP_CWORD]}\""
      lines << "    local prev=\"${COMP_WORDS[COMP_CWORD-1]}\""
      lines << ""

      if @cli.subcommands.any?
        lines << bash_with_subcommands(program)
      else
        lines << bash_flat(program)
      end

      lines << "}"
      lines << "complete -F #{func_name} #{program}"
      lines.join("\n")
    end

    def zsh : String
      program = @cli.program_name

      lines = [] of String
      lines << "#compdef #{program}"
      lines << ""
      lines << "_#{program.gsub("-", "_")}() {"

      if @cli.subcommands.any?
        lines << zsh_with_subcommands(program)
      else
        lines << zsh_flat(program)
      end

      lines << "}"
      lines << ""
      lines << "_#{program.gsub("-", "_")} \"$@\""
      lines.join("\n")
    end

    def fish : String
      program = @cli.program_name

      lines = [] of String
      lines << "# Disable file completion by default"
      lines << "complete -c #{program} -f"
      lines << ""

      if @cli.subcommands.any?
        lines << fish_with_subcommands(program)
      else
        lines << fish_flat(program)
      end

      lines.join("\n")
    end

    private def bash_with_subcommands(program : String) : String
      lines = [] of String

      # Collect top-level subcommands (escaped for shell safety)
      subcmd_names = @cli.subcommands.keys.map { |n| escape_bash(n) }
      top_level_words = subcmd_names.join(" ") + " --help -h"

      lines << "    # Top-level: subcommands"
      lines << "    if [[ ${COMP_CWORD} -eq 1 ]]; then"
      lines << "        COMPREPLY=( $(compgen -W \"#{top_level_words}\" -- \"$cur\") )"
      lines << "        return"
      lines << "    fi"
      lines << ""
      lines << "    # Subcommand-specific completions"
      lines << "    local cmd=\"${COMP_WORDS[1]}\""
      lines << "    case \"$cmd\" in"

      @cli.subcommands.each do |name, subcmd|
        case subcmd
        when Schema
          lines << bash_subcommand_case(name, subcmd, 2)
        when CLI
          lines << bash_nested_cli_case(name, subcmd, 2)
        end
      end

      lines << "    esac"
      lines.join("\n")
    end

    private def bash_subcommand_case(name : String, schema : Schema, depth : Int32) : String
      lines = [] of String
      indent = "    " * depth
      flags = collect_flags(schema)

      # Build flag words (escaped for shell safety)
      flag_words = [] of String
      flags.each do |flag|
        flag_words << "--#{escape_bash(flag.long)}"
        if short = flag.short
          flag_words << "-#{escape_bash(short)}"
        end
      end
      flag_words << "--help" << "-h"

      # Build enum cases
      enum_flags = flags.select { |f| f.enum_values }

      escaped_name = escape_bash(name)
      lines << "#{indent}#{escaped_name})"
      if enum_flags.any?
        lines << "#{indent}    case \"$prev\" in"
        enum_flags.each do |flag|
          flag_patterns = ["--#{escape_bash(flag.long)}"]
          if short = flag.short
            flag_patterns << "-#{escape_bash(short)}"
          end
          enum_values_escaped = flag.enum_values.not_nil!.map { |v| escape_bash(v) }.join(" ")
          lines << "#{indent}        #{flag_patterns.join("|")})"
          lines << "#{indent}            COMPREPLY=( $(compgen -W \"#{enum_values_escaped}\" -- \"$cur\") )"
          lines << "#{indent}            ;;"
        end
        lines << "#{indent}        *)"
        lines << "#{indent}            COMPREPLY=( $(compgen -W \"#{flag_words.join(" ")}\" -- \"$cur\") )"
        lines << "#{indent}            ;;"
        lines << "#{indent}    esac"
      else
        lines << "#{indent}    COMPREPLY=( $(compgen -W \"#{flag_words.join(" ")}\" -- \"$cur\") )"
      end
      lines << "#{indent}    ;;"

      lines.join("\n")
    end

    private def bash_nested_cli_case(name : String, cli : CLI, depth : Int32) : String
      lines = [] of String
      indent = "    " * depth

      # Get nested subcommand names (escaped for shell safety)
      nested_names = cli.subcommands.keys.map { |n| escape_bash(n) }
      escaped_name = escape_bash(name)

      lines << "#{indent}#{escaped_name})"
      lines << "#{indent}    if [[ ${COMP_CWORD} -eq 2 ]]; then"
      lines << "#{indent}        COMPREPLY=( $(compgen -W \"#{nested_names.join(" ")} --help -h\" -- \"$cur\") )"
      lines << "#{indent}        return"
      lines << "#{indent}    fi"
      lines << "#{indent}    local subcmd=\"${COMP_WORDS[2]}\""
      lines << "#{indent}    case \"$subcmd\" in"

      cli.subcommands.each do |sub_name, sub|
        case sub
        when Schema
          lines << bash_subcommand_case(sub_name, sub, depth + 1)
        when CLI
          # For deeper nesting, simplify to just --help
          lines << "#{indent}        #{escape_bash(sub_name)})"
          lines << "#{indent}            COMPREPLY=( $(compgen -W \"--help -h\" -- \"$cur\") )"
          lines << "#{indent}            ;;"
        end
      end

      lines << "#{indent}    esac"
      lines << "#{indent}    ;;"

      lines.join("\n")
    end

    private def bash_flat(program : String) : String
      lines = [] of String

      if schema = @cli.schema
        flags = collect_flags(schema)
        # Build flag words (escaped for shell safety)
        flag_words = [] of String
        flags.each do |flag|
          flag_words << "--#{escape_bash(flag.long)}"
          if short = flag.short
            flag_words << "-#{escape_bash(short)}"
          end
        end
        flag_words << "--help" << "-h"

        enum_flags = flags.select { |f| f.enum_values }

        if enum_flags.any?
          lines << "    case \"$prev\" in"
          enum_flags.each do |flag|
            flag_patterns = ["--#{escape_bash(flag.long)}"]
            if short = flag.short
              flag_patterns << "-#{escape_bash(short)}"
            end
            enum_values_escaped = flag.enum_values.not_nil!.map { |v| escape_bash(v) }.join(" ")
            lines << "        #{flag_patterns.join("|")})"
            lines << "            COMPREPLY=( $(compgen -W \"#{enum_values_escaped}\" -- \"$cur\") )"
            lines << "            ;;"
          end
          lines << "        *)"
          lines << "            COMPREPLY=( $(compgen -W \"#{flag_words.join(" ")}\" -- \"$cur\") )"
          lines << "            ;;"
          lines << "    esac"
        else
          lines << "    COMPREPLY=( $(compgen -W \"#{flag_words.join(" ")}\" -- \"$cur\") )"
        end
      else
        lines << "    COMPREPLY=( $(compgen -W \"--help -h\" -- \"$cur\") )"
      end

      lines.join("\n")
    end

    private def zsh_with_subcommands(program : String) : String
      lines = [] of String

      lines << "    local -a commands"
      lines << "    commands=("

      @cli.subcommands.each do |name, subcmd|
        desc = case subcmd
               when Schema
                 subcmd.root.description || name
               when CLI
                 name
               else
                 name
               end
        lines << "        '#{name}:#{escape_zsh(desc)}'"
      end

      lines << "    )"
      lines << ""
      lines << "    _arguments -C \\"
      lines << "        '1:command:->command' \\"
      lines << "        '*::arg:->args'"
      lines << ""
      lines << "    case \"$state\" in"
      lines << "        command)"
      lines << "            _describe 'command' commands"
      lines << "            ;;"
      lines << "        args)"
      lines << "            case \"$words[1]\" in"

      @cli.subcommands.each do |name, subcmd|
        case subcmd
        when Schema
          lines << zsh_subcommand_case(name, subcmd)
        when CLI
          lines << zsh_nested_cli_case(name, subcmd)
        end
      end

      lines << "            esac"
      lines << "            ;;"
      lines << "    esac"

      lines.join("\n")
    end

    private def zsh_subcommand_case(name : String, schema : Schema) : String
      lines = [] of String
      flags = collect_flags(schema)

      lines << "                #{name})"
      lines << "                    _arguments \\"

      flags.each do |flag|
        lines << "                        #{build_zsh_flag_arg(flag)} \\"
      end

      # Remove trailing backslash from last line if there are flags
      if flags.any?
        lines[-1] = lines[-1].rstrip(" \\")
      else
        lines << "                        '--help[Show help]'"
      end

      lines << "                    ;;"

      lines.join("\n")
    end

    private def zsh_nested_cli_case(name : String, cli : CLI) : String
      lines = [] of String

      lines << "                #{name})"
      lines << "                    local -a #{name}_commands"
      lines << "                    #{name}_commands=("

      cli.subcommands.each do |sub_name, sub|
        desc = case sub
               when Schema
                 sub.root.description || sub_name
               else
                 sub_name
               end
        lines << "                        '#{sub_name}:#{escape_zsh(desc)}'"
      end

      lines << "                    )"
      lines << "                    _describe '#{name} command' #{name}_commands"
      lines << "                    ;;"

      lines.join("\n")
    end

    private def zsh_flat(program : String) : String
      lines = [] of String

      if schema = @cli.schema
        flags = collect_flags(schema)

        lines << "    _arguments \\"

        flags.each do |flag|
          lines << "        #{build_zsh_flag_arg(flag)} \\"
        end

        lines << "        '--help[Show help]'"
      else
        lines << "    _arguments '--help[Show help]'"
      end

      lines.join("\n")
    end

    private def fish_with_subcommands(program : String) : String
      lines = [] of String

      lines << "# Subcommands"
      @cli.subcommands.each do |name, subcmd|
        desc = case subcmd
               when Schema
                 subcmd.root.description
               else
                 nil
               end
        if desc
          lines << "complete -c #{program} -n \"__fish_use_subcommand\" -a \"#{name}\" -d \"#{escape_fish(desc)}\""
        else
          lines << "complete -c #{program} -n \"__fish_use_subcommand\" -a \"#{name}\""
        end
      end

      lines << ""

      @cli.subcommands.each do |name, subcmd|
        case subcmd
        when Schema
          lines << fish_subcommand_flags(program, name, subcmd)
        when CLI
          lines << fish_nested_cli(program, name, subcmd)
        end
        lines << ""
      end

      lines.join("\n")
    end

    private def fish_subcommand_flags(program : String, name : String, schema : Schema) : String
      lines = [] of String
      flags = collect_flags(schema)

      lines << "# #{name} subcommand options"
      flags.each do |flag|
        lines << build_fish_flag_line(program, flag, "\"__fish_seen_subcommand_from #{name}\"")
      end

      lines.join("\n")
    end

    private def fish_nested_cli(program : String, parent_name : String, cli : CLI) : String
      lines = [] of String

      lines << "# #{parent_name} nested subcommands"
      cli.subcommands.each do |name, subcmd|
        desc = case subcmd
               when Schema
                 subcmd.root.description
               else
                 nil
               end

        condition = "__fish_seen_subcommand_from #{parent_name}; and not __fish_seen_subcommand_from #{cli.subcommands.keys.join(" ")}"
        if desc
          lines << "complete -c #{program} -n \"#{condition}\" -a \"#{name}\" -d \"#{escape_fish(desc)}\""
        else
          lines << "complete -c #{program} -n \"#{condition}\" -a \"#{name}\""
        end
      end

      # Add flags for each nested subcommand
      cli.subcommands.each do |sub_name, sub|
        case sub
        when Schema
          condition = "\"__fish_seen_subcommand_from #{parent_name}; and __fish_seen_subcommand_from #{sub_name}\""
          collect_flags(sub).each do |flag|
            lines << build_fish_flag_line(program, flag, condition)
          end
        end
      end

      lines.join("\n")
    end

    private def fish_flat(program : String) : String
      lines = [] of String

      if schema = @cli.schema
        lines << "# Options"
        collect_flags(schema).each do |flag|
          lines << build_fish_flag_line(program, flag, nil)
        end
      end

      lines.join("\n")
    end

    private def build_zsh_flag_arg(flag : FlagInfo) : String
      desc = escape_zsh(flag.description || flag.long)
      enum_suffix = if enum_values = flag.enum_values
                      ":value:(#{enum_values.join(" ")})"
                    else
                      ""
                    end

      if short = flag.short
        "{-#{short},--#{flag.long}}'[#{desc}]#{enum_suffix}'"
      else
        "'--#{flag.long}[#{desc}]#{enum_suffix}'"
      end
    end

    private def build_fish_flag_line(program : String, flag : FlagInfo, condition : String?) : String
      parts = ["complete", "-c", program]
      if cond = condition
        parts << "-n" << cond
      end
      if short = flag.short
        parts << "-s" << short
      end
      parts << "-l" << flag.long
      if desc = flag.description
        parts << "-d" << "\"#{escape_fish(desc)}\""
      end
      if enum_values = flag.enum_values
        parts << "-xa" << "\"#{enum_values.join(" ")}\""
      end
      parts.join(" ")
    end

    private def collect_flags(schema : Schema) : Array(FlagInfo)
      flags = [] of FlagInfo
      root = resolve_property(schema.root, schema)
      positional_names = schema.positional

      if props = root.properties
        props.each do |name, prop|
          next if positional_names.includes?(name)
          resolved = resolve_property(prop, schema)

          enum_values = if ev = resolved.enum_values
                          ev.map { |v| v.raw.to_s }
                        else
                          nil
                        end

          flags << FlagInfo.new(
            long: name,
            short: resolved.short,
            description: resolved.description,
            enum_values: enum_values
          )
        end
      end

      flags
    end

    private def resolve_property(prop : Property, schema : Schema) : Property
      if ref = prop.ref
        schema.resolve_ref(ref) || prop
      else
        prop
      end
    end

    # Escape for bash double-quoted strings
    private def escape_bash(str : String) : String
      str.gsub("\\", "\\\\")
         .gsub("\"", "\\\"")
         .gsub("$", "\\$")
         .gsub("`", "\\`")
    end

    private def escape_zsh(str : String?) : String
      return "" unless str
      str.gsub("'", "'\\''").gsub("[", "\\[").gsub("]", "\\]")
    end

    private def escape_fish(str : String?) : String
      return "" unless str
      str.gsub("\"", "\\\"").gsub("$", "\\$")
    end
  end
end
