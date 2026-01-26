require "json"

module Jargon
  class Result
    getter data : JSON::Any
    getter errors : Array(String)
    getter subcommand : String?
    getter? help_requested : Bool
    getter help_subcommand : String?
    getter completion_shell : String?

    def initialize(@data : JSON::Any, @errors : Array(String) = [] of String, @subcommand : String? = nil,
                   @help_requested : Bool = false, @help_subcommand : String? = nil, @completion_shell : String? = nil)
    end

    def initialize(data : Hash(String, JSON::Any), @errors : Array(String) = [] of String, @subcommand : String? = nil,
                   @help_requested : Bool = false, @help_subcommand : String? = nil, @completion_shell : String? = nil)
      @data = JSON::Any.new(data)
    end

    def completion_requested? : Bool
      !@completion_shell.nil?
    end

    def valid? : Bool
      errors.empty?
    end

    def to_json : String
      data.to_json
    end

    def to_pretty_json : String
      data.to_pretty_json
    end

    def [](key : String) : JSON::Any
      data[key]
    end

    def []?(key : String) : JSON::Any?
      data[key]?
    end
  end
end
