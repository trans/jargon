module CLJ
  class Property
    enum Type
      String
      Integer
      Number
      Boolean
      Array
      Object
      Null
    end

    getter name : String
    getter type : Type
    getter description : String?
    getter required : Bool
    getter default : JSON::Any?
    getter enum_values : Array(JSON::Any)?
    getter properties : Hash(String, Property)?
    getter items : Property?
    getter ref : String?

    def initialize(
      @name : String,
      @type : Type,
      @description : String? = nil,
      @required : Bool = false,
      @default : JSON::Any? = nil,
      @enum_values : Array(JSON::Any)? = nil,
      @properties : Hash(String, Property)? = nil,
      @items : Property? = nil,
      @ref : String? = nil
    )
    end

    def self.from_json(name : String, json : JSON::Any, required_fields : Array(String) = [] of String) : Property
      type = parse_type(json["type"]?.try(&.as_s?) || "string")
      description = json["description"]?.try(&.as_s?)
      default = json["default"]?
      enum_values = json["enum"]?.try(&.as_a?)
      ref = json["$ref"]?.try(&.as_s?)
      is_required = required_fields.includes?(name)

      properties = if type.object? && (props = json["properties"]?)
        nested_required = json["required"]?.try(&.as_a.map(&.as_s)) || [] of String
        props.as_h.map do |prop_name, prop_schema|
          {prop_name, Property.from_json(prop_name, prop_schema, nested_required)}
        end.to_h
      end

      items = if type.array? && (item_schema = json["items"]?)
        Property.from_json("items", item_schema)
      end

      Property.new(
        name: name,
        type: type,
        description: description,
        required: is_required,
        default: default,
        enum_values: enum_values,
        properties: properties,
        items: items,
        ref: ref
      )
    end

    private def self.parse_type(type_str : String) : Type
      case type_str.downcase
      when "string"  then Type::String
      when "integer" then Type::Integer
      when "number"  then Type::Number
      when "boolean" then Type::Boolean
      when "array"   then Type::Array
      when "object"  then Type::Object
      when "null"    then Type::Null
      else                Type::String
      end
    end
  end
end
