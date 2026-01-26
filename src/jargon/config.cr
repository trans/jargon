require "yaml"

module Jargon
  class CLI
    # Load config from standard locations.
    # Supports YAML (.yaml, .yml) and JSON (.json) files.
    #
    # Paths searched (in order):
    # 1. ./.config/{program_name}.yaml/.yml/.json (project local, flat)
    # 2. ./.config/{program_name}/config.yaml/.yml/.json (project local, directory)
    # 3. $XDG_CONFIG_HOME/{program_name}.yaml/.yml/.json (user global, flat)
    # 4. $XDG_CONFIG_HOME/{program_name}/config.yaml/.yml/.json (user global, directory)
    #
    # With merge: true (default), merges all configs found (project wins over user).
    # With merge: false, returns first config found.
    # Returns nil if no config file found.
    def load_config(*, merge : Bool = true) : JSON::Any?
      if merge
        load_config_merged
      else
        load_config_first
      end
    end

    # Returns the list of config paths that would be searched
    def config_paths : Array(String)
      xdg_config = ENV["XDG_CONFIG_HOME"]? || Path.home.join(".config").to_s
      bases = [
        "./.config/#{@program_name}",
        "./.config/#{@program_name}/config",
        "#{xdg_config}/#{@program_name}",
        "#{xdg_config}/#{@program_name}/config",
      ]
      # For each base, check .yaml, .yml, .json (in that order)
      bases.flat_map { |base| ["#{base}.yaml", "#{base}.yml", "#{base}.json"] }
    end

    private def load_config_first : JSON::Any?
      config_paths.each do |path|
        if File.exists?(path)
          return parse_config_file(path)
        end
      end
      nil
    end

    private def load_config_merged : JSON::Any?
      # Load in reverse order (user first, project last) so project wins
      merged = {} of String => JSON::Any
      config_paths.reverse.each do |path|
        if File.exists?(path)
          begin
            if data = parse_config_file(path).try(&.as_h?)
              merged.merge!(data)
            end
          rescue
            # Skip invalid files
          end
        end
      end
      merged.empty? ? nil : JSON::Any.new(merged)
    end

    private def parse_config_file(path : String) : JSON::Any?
      content = File.read(path)
      case File.extname(path).downcase
      when ".yaml", ".yml"
        JSON.parse(YAML.parse(content).to_json)
      when ".json"
        JSON.parse(content)
      else
        nil
      end
    rescue
      nil
    end
  end
end
