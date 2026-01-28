require "../src/jargon"
require "json"

# Test with type: object
json = JSON.parse(%({"type":"object","properties":{"verbose":{"type":"boolean","short":"v"},"format":{"type":"string"},"file":{"type":"string"}},"name":"export"}))
schema = Jargon::Schema.from_json_any(json)
puts "With type: object"
if props = schema.root.properties
  props.each do |pname, prop|
    puts "  #{pname}: type=#{prop.type}, short=#{prop.short}"
  end
else
  puts "  (no properties)"
end

# Test without type: object
json2 = JSON.parse(%({"properties":{"verbose":{"type":"boolean","short":"v"},"format":{"type":"string"},"file":{"type":"string"}},"name":"export"}))
schema2 = Jargon::Schema.from_json_any(json2)
puts "\nWithout type: object"
if props = schema2.root.properties
  props.each do |pname, prop|
    puts "  #{pname}: type=#{prop.type}, short=#{prop.short}"
  end
else
  puts "  (no properties)"
end
