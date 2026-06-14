require "./schema"

module Jargon
  # Shell completion: generates a small "shim" script per shell that, on every
  # Tab, forwards the cursor position and typed words to the program itself
  # (the hidden `__complete` verb). The program then computes candidates from
  # the schema plus any registered dynamic completers — so static (flags,
  # enums, subcommands) and dynamic (live app data) completion share one path.
  class Completion
    # Hidden subcommand the generated shim invokes at completion time. Never
    # written by the developer — it is an internal token between the shim and
    # CLI#handle_completion.
    COMPLETE_VERB = "__complete"

    # Context handed to a registered completer block. `partial` is the token
    # being completed; `words` is the full command line as the shell tokenized
    # it (program name at index 0); `subcommand` is the resolved subcommand
    # path (nil at top level); `arguments` is a lenient parse of what has been
    # typed so far, for filtering.
    struct Context
      getter partial : String
      getter words : Array(String)
      getter subcommand : String?
      getter arguments : Hash(String, String)

      def initialize(@partial : String, @words : Array(String), @subcommand : String?, @arguments : Hash(String, String))
      end
    end

    def initialize(@cli : CLI)
      @words = [] of String
    end

    # ---- shim generation -------------------------------------------------

    def bash(command : String) : String
      program = @cli.program_name
      func = "_#{sanitize(program)}_complete"
      <<-BASH
      #{func}() {
          readarray -t COMPREPLY < <(#{command} #{COMPLETE_VERB} "$COMP_CWORD" "${COMP_WORDS[@]}")
      }
      complete -F #{func} #{program}
      BASH
    end

    def zsh(command : String) : String
      program = @cli.program_name
      func = "_#{sanitize(program)}"
      <<-ZSH
      #compdef #{program}
      #{func}() {
          local -a candidates
          candidates=("${(@f)$(#{command} #{COMPLETE_VERB} $((CURRENT - 1)) $words)}")
          compadd -U -- $candidates
      }
      compdef #{func} #{program}
      ZSH
    end

    def fish(command : String) : String
      program = @cli.program_name
      func = "__#{sanitize(program)}_complete"
      <<-FISH
      function #{func}
          set -l tokens (commandline --current-process --tokenize --cut-at-cursor)
          set -l current (commandline --current-token)
          #{command} #{COMPLETE_VERB} (count $tokens) $tokens $current
      end
      complete -c #{program} -f -a '(#{func})'
      FISH
    end

    private def sanitize(name : String) : String
      name.gsub(/[^a-zA-Z0-9_]/, "_")
    end

    # ---- runtime engine --------------------------------------------------

    # Compute completion candidates for a tokenized command line. `words`
    # includes the program name at index 0; `cword` is the index of the word
    # under the cursor (may equal words.size when completing a fresh token).
    def candidates(words : Array(String), cword : Int32) : Array(String)
      @words = words
      partial = (cword >= 0 && cword < words.size) ? words[cword] : ""
      args = words.size > 1 ? words[1..] : [] of String
      complete_cli(@cli, args, cword - 1, "", partial)
    end

    private def complete_cli(cli : CLI, args : Array(String), cursor : Int32, path : String, partial : String) : Array(String)
      unless cli.subcommands.empty?
        # Completing the subcommand token itself.
        if cursor <= 0
          names = cli.subcommands.keys
          names += ["--help", "-h"] if partial.starts_with?("-")
          return filter(names, partial)
        end

        # Descend into the chosen subcommand.
        name = args[0]?
        sub = name ? cli.subcommands[name]? : nil
        sub_path = name ? join(path, name) : path
        case sub
        when CLI    then return complete_cli(sub, args[1..], cursor - 1, sub_path, partial)
        when Schema then return complete_schema(sub, args[1..], cursor - 1, sub_path, partial)
        else             return [] of String
        end
      end

      if schema = cli.schema
        return complete_schema(schema, args, cursor, path, partial)
      end

      [] of String
    end

    private def complete_schema(schema : Schema, args : Array(String), cursor : Int32, path : String, partial : String) : Array(String)
      # Completing a flag name.
      return flag_name_candidates(schema, partial) if partial.starts_with?("-")

      # Completing the value of the preceding value-taking flag. This is
      # terminal: the current token IS that flag's value, so never fall through
      # to positional completion (an absent enum/completer just means no
      # candidates).
      if cursor >= 1 && (prev = args[cursor - 1]?) && prev.starts_with?("-")
        if (field = field_for_flag(prev, schema)) && !boolean?(schema, field)
          return value_candidates(schema, field, path, partial, args) || [] of String
        end
      end

      # Completing a positional.
      if field = positional_at(schema, args, cursor)
        return value_candidates(schema, field, path, partial, args) || [] of String
      end

      [] of String
    end

    private def value_candidates(schema : Schema, field : String, path : String, partial : String, args : Array(String)) : Array(String)?
      key = path.empty? ? field : "#{path}.#{field}"
      if completer = @cli.completers[key]?
        ctx = Context.new(partial, @words, path.empty? ? nil : path, collect_arguments(schema, args))
        return completer.call(ctx)
      end

      if (prop = props_of(schema)[field]?) && (enum_values = prop.enum_values)
        return filter(enum_values.map { |v| v.as_s? || v.to_json }, partial)
      end

      nil
    end

    private def flag_name_candidates(schema : Schema, partial : String) : Array(String)
      positional = schema.positional
      tokens = ["--help", "-h"]
      props_of(schema).each do |name, prop|
        next if positional.includes?(name)
        tokens << "--#{name}"
        tokens << "-#{prop.short}" if prop.short
      end
      filter(tokens, partial)
    end

    # Which positional slot the cursor sits in, accounting for flags (and the
    # values non-boolean flags consume). Returns the last positional when it is
    # a variadic array and the cursor is past the declared slots.
    private def positional_at(schema : Schema, args : Array(String), cursor : Int32) : String?
      names = schema.positional
      return nil if names.empty?

      idx = positional_index(schema, args, Math.min(cursor, args.size))
      return names[idx] if idx < names.size

      last = names.last?
      (last && array?(schema, last)) ? last : nil
    end

    # Count how many positional slots are filled within args[0...limit],
    # skipping flags and the values that value-taking flags consume.
    private def positional_index(schema : Schema, args : Array(String), limit : Int32) : Int32
      idx = 0
      i = 0
      while i < limit
        tok = args[i]
        if value_taking_flag?(schema, tok) && i + 1 < limit
          i += 2
        elsif skip_token?(tok)
          i += 1
        else
          idx += 1
          i += 1
        end
      end
      idx
    end

    private def value_taking_flag?(schema : Schema, token : String) : Bool
      return false unless token.starts_with?("-")
      if field = field_for_flag(token, schema)
        !boolean?(schema, field)
      else
        false
      end
    end

    private def skip_token?(token : String) : Bool
      token.starts_with?("-") || token.includes?("=") || token.includes?(":")
    end

    private def collect_arguments(schema : Schema, args : Array(String)) : Hash(String, String)
      result = {} of String => String
      i = 0
      while i < args.size
        tok = args[i]
        if tok.starts_with?("--") && tok.includes?("=")
          k, v = tok[2..].split("=", 2)
          result[k] = v
          i += 1
        elsif tok.starts_with?("-")
          field = field_for_flag(tok, schema)
          if field && !boolean?(schema, field) && i + 1 < args.size
            result[field] = args[i + 1]
            i += 2
          else
            result[field || tok] = "true"
            i += 1
          end
        elsif tok.includes?("=")
          k, v = tok.split("=", 2)
          result[k] = v
          i += 1
        else
          i += 1
        end
      end
      result
    end

    # ---- small schema helpers --------------------------------------------

    private def props_of(schema : Schema) : Hash(String, Property)
      schema.root.properties || {} of String => Property
    end

    private def field_for_flag(token : String, schema : Schema) : String?
      if token.starts_with?("--")
        name = token[2..].split("=", 2)[0]
        props_of(schema).has_key?(name) ? name : nil
      elsif token.starts_with?("-")
        short = token[1..]
        props_of(schema).each { |field, prop| return field if prop.short == short }
        nil
      end
    end

    private def boolean?(schema : Schema, field : String) : Bool
      props_of(schema)[field]?.try(&.type.boolean?) || false
    end

    private def array?(schema : Schema, field : String) : Bool
      props_of(schema)[field]?.try(&.type.array?) || false
    end

    private def join(path : String, name : String) : String
      path.empty? ? name : "#{path}.#{name}"
    end

    private def filter(candidates : Array(String), partial : String) : Array(String)
      return candidates if partial.empty?
      candidates.select(&.starts_with?(partial))
    end
  end
end
