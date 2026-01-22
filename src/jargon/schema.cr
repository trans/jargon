require "json"
require "./schema/property"

module Jargon
  class Schema
    getter root : Property
    getter definitions : Hash(String, Property)
    getter positional : Array(String)

    def initialize(@root : Property, @definitions : Hash(String, Property) = {} of String => Property, @positional : Array(String) = [] of String)
    end

    def self.from_json(json_string : String) : Schema
      json = JSON.parse(json_string)
      from_json_any(json)
    end

    def self.from_file(path : String) : Schema
      json_string = File.read(path)
      from_json(json_string)
    end

    def self.from_json_any(json : JSON::Any) : Schema
      required_fields = json["required"]?.try(&.as_a.map(&.as_s)) || [] of String
      positional = json["positional"]?.try(&.as_a.map(&.as_s)) || [] of String

      root = Property.from_json("root", json, required_fields)

      definitions = if defs = json["definitions"]? || json["$defs"]?
        defs.as_h.map do |def_name, def_schema|
          {def_name, Property.from_json(def_name, def_schema)}
        end.to_h
      else
        {} of String => Property
      end

      Schema.new(root, definitions, positional)
    end

    def resolve_ref(ref : String) : Property?
      return nil unless ref.starts_with?("#/")

      parts = ref[2..].split("/")
      return nil unless parts.size >= 2

      case parts[0]
      when "definitions", "$defs"
        definitions[parts[1]]?
      else
        nil
      end
    end
  end
end
