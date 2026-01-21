require "./clj/schema"
require "./clj/cli"
require "./clj/result"

module CLJ
  VERSION = "0.1.0"

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
end
