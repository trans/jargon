require "./spec_helper"

describe CLJ do
  describe "basic parsing" do
    it "parses string values with equals style" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["name=John"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
    end

    it "parses string values with colon style" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["name:John"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
    end

    it "parses string values with traditional style" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--name", "John"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
    end

    it "parses --key=value style" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--name=John"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
    end
  end

  describe "type coercion" do
    it "coerces integer values" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["count=42"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(42)
    end

    it "coerces number values" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["rate=3.14"])
      result.valid?.should be_true
      result["rate"].as_f.should eq(3.14)
    end

    it "coerces boolean values" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["verbose=true"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true

      result = cli.parse(["verbose=false"])
      result["verbose"].as_bool.should be_false
    end

    it "handles boolean flags without value" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--verbose"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
    end

    it "coerces array values" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "tags": {"type": "array", "items": {"type": "string"}}
        }
      }))

      result = cli.parse(["tags=a,b,c"])
      result.valid?.should be_true
      result["tags"].as_a.map(&.as_s).should eq(["a", "b", "c"])
    end
  end

  describe "nested objects" do
    it "parses nested properties with dot notation" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "user": {
            "type": "object",
            "properties": {
              "name": {"type": "string"},
              "age": {"type": "integer"}
            }
          }
        }
      }))

      result = cli.parse(["user.name=John", "user.age=30"])
      result.valid?.should be_true
      result["user"]["name"].as_s.should eq("John")
      result["user"]["age"].as_i64.should eq(30)
    end

    it "handles deeply nested properties" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "config": {
            "type": "object",
            "properties": {
              "database": {
                "type": "object",
                "properties": {
                  "host": {"type": "string"}
                }
              }
            }
          }
        }
      }))

      result = cli.parse(["config.database.host=localhost"])
      result.valid?.should be_true
      result["config"]["database"]["host"].as_s.should eq("localhost")
    end
  end

  describe "validation" do
    it "validates required fields" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      result = cli.parse([] of String)
      result.valid?.should be_false
      result.errors.should contain("Missing required field: name")
    end

    it "validates enum values" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "color": {"type": "string", "enum": ["red", "green", "blue"]}
        }
      }))

      result = cli.parse(["color=red"])
      result.valid?.should be_true

      result = cli.parse(["color=yellow"])
      result.valid?.should be_false
    end

    it "validates types" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["count=42"])
      result.valid?.should be_true
    end
  end

  describe "defaults" do
    it "applies default values" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string", "default": "anonymous"}
        }
      }))

      result = cli.parse([] of String)
      result["name"].as_s.should eq("anonymous")
    end

    it "does not override provided values with defaults" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string", "default": "anonymous"}
        }
      }))

      result = cli.parse(["name=John"])
      result["name"].as_s.should eq("John")
    end
  end

  describe "help" do
    it "generates help text" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "The user name"}
        },
        "required": ["name"]
      }), "myapp")

      help = cli.help
      help.should contain("myapp")
      help.should contain("--name")
      help.should contain("required")
      help.should contain("The user name")
    end
  end

  describe "mixed styles" do
    it "accepts mixed argument styles" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "integer"},
          "active": {"type": "boolean"}
        }
      }))

      result = cli.parse(["name=John", "--age", "30", "active:true"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
      result["age"].as_i64.should eq(30)
      result["active"].as_bool.should be_true
    end
  end

  describe "JSON output" do
    it "outputs valid JSON" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["name=John", "count=42"])
      json = result.to_json
      parsed = JSON.parse(json)
      parsed["name"].as_s.should eq("John")
      parsed["count"].as_i64.should eq(42)
    end
  end

  describe "$ref resolution" do
    it "resolves local $ref to $defs" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "billing": {"$ref": "#/$defs/address"},
          "shipping": {"$ref": "#/$defs/address"}
        },
        "$defs": {
          "address": {
            "type": "object",
            "properties": {
              "street": {"type": "string"},
              "city": {"type": "string"}
            }
          }
        }
      }))

      result = cli.parse(["billing.street=123 Main", "billing.city=NYC", "shipping.city=LA"])
      result.valid?.should be_true
      result["billing"]["street"].as_s.should eq("123 Main")
      result["billing"]["city"].as_s.should eq("NYC")
      result["shipping"]["city"].as_s.should eq("LA")
    end

    it "resolves local $ref to definitions" do
      cli = CLJ.from_json(%({
        "type": "object",
        "properties": {
          "user": {"$ref": "#/definitions/person"}
        },
        "definitions": {
          "person": {
            "type": "object",
            "properties": {
              "name": {"type": "string"},
              "age": {"type": "integer"}
            }
          }
        }
      }))

      result = cli.parse(["user.name=John", "user.age=30"])
      result.valid?.should be_true
      result["user"]["name"].as_s.should eq("John")
      result["user"]["age"].as_i64.should eq(30)
    end
  end
end
