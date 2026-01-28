require "./spec_helper"

describe Jargon do
  describe "API" do
    it "Jargon::CLI.from_json creates CLI from JSON schema" do
      cli = Jargon::CLI.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }), "myapp")

      cli.should be_a(Jargon::CLI)
      cli.program_name.should eq("myapp")
      result = cli.parse(["--name", "test"])
      result["name"].as_s.should eq("test")
    end

    it "Jargon.cli with json: creates CLI from JSON string" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      cli.should be_a(Jargon::CLI)
      cli.program_name.should eq("myapp")
      result = cli.parse(["--verbose"])
      result["verbose"].as_bool.should be_true
    end

    it "Jargon.cli with file: creates CLI from file" do
      # Use existing schema file if available, or create temp one
      File.write("/tmp/test_schema.json", %({"type": "object", "properties": {"name": {"type": "string"}}}))
      begin
        cli = Jargon.cli("myapp", file: "/tmp/test_schema.json")
        cli.should be_a(Jargon::CLI)
        cli.program_name.should eq("myapp")
        result = cli.parse(["--name", "test"])
        result["name"].as_s.should eq("test")
      ensure
        File.delete("/tmp/test_schema.json")
      end
    end

    it "Jargon.from_json remains for backwards compatibility" do
      cli = Jargon.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }), "myapp")

      cli.should be_a(Jargon::CLI)
      result = cli.parse(["--name", "test"])
      result["name"].as_s.should eq("test")
    end
  end

  describe "basic parsing" do
    it "parses string values with equals style" do
      cli = Jargon.cli("myapp", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--verbose"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
    end

    it "handles boolean flags with explicit true/false value" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "enabled": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--enabled", "false"])
      result.valid?.should be_true
      result["enabled"].as_bool.should be_false

      result = cli.parse(["--enabled", "true"])
      result.valid?.should be_true
      result["enabled"].as_bool.should be_true

      result = cli.parse(["--enabled", "no"])
      result.valid?.should be_true
      result["enabled"].as_bool.should be_false
    end

    it "does not consume non-boolean value after boolean flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "verbose": {"type": "boolean"},
          "file": {"type": "string"}
        }
      }))

      result = cli.parse(["--verbose", "output.txt"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
      result["file"].as_s.should eq("output.txt")
    end

    it "accepts various boolean value formats" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "flag": {"type": "boolean"}
        }
      }))

      %w[true yes on 1 TRUE Yes ON].each do |val|
        result = cli.parse(["flag=#{val}"])
        result.valid?.should be_true
        result["flag"].as_bool.should be_true
      end

      %w[false no off 0 FALSE No OFF].each do |val|
        result = cli.parse(["flag=#{val}"])
        result.valid?.should be_true
        result["flag"].as_bool.should be_false
      end
    end

    it "errors on invalid boolean values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["verbose=treu"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid boolean value 'treu'")
      result.errors.first.should contain("true/false")
    end

    it "coerces array values" do
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["count=42"])
      result.valid?.should be_true
    end

    it "validates array item enums" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "tags": {
            "type": "array",
            "items": {"type": "string", "enum": ["alpha", "beta", "stable"]}
          }
        }
      }))

      result = cli.parse(["--tags", "alpha,beta"])
      result.valid?.should be_true

      result = cli.parse(["--tags", "alpha,invalid,beta"])
      result.valid?.should be_false
      result.errors.first.should contain("tags[1]")
      result.errors.first.should contain("must be one of")
    end

    it "validates minimum and maximum for integers" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "port": {"type": "integer", "minimum": 1, "maximum": 65535}
        }
      }))

      result = cli.parse(["--port", "8080"])
      result.valid?.should be_true

      result = cli.parse(["--port", "0"])
      result.valid?.should be_false
      result.errors.first.should contain(">= 1")

      result = cli.parse(["--port", "70000"])
      result.valid?.should be_false
      result.errors.first.should contain("<= 65535")
    end

    it "validates minimum and maximum for numbers" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "ratio": {"type": "number", "minimum": 0.0, "maximum": 1.0}
        }
      }))

      result = cli.parse(["--ratio", "0.5"])
      result.valid?.should be_true

      result = cli.parse(["--ratio", "-0.1"])
      result.valid?.should be_false

      result = cli.parse(["--ratio", "1.5"])
      result.valid?.should be_false
    end

    it "validates string patterns" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "code": {"type": "string", "pattern": "^[A-Z]{2}[0-9]{3}$"}
        }
      }))

      result = cli.parse(["--code", "AB123"])
      result.valid?.should be_true

      result = cli.parse(["--code", "invalid"])
      result.valid?.should be_false
      result.errors.first.should contain("must match pattern")
    end

    it "formats enum error messages nicely" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "level": {"type": "string", "enum": ["debug", "info", "warn"]}
        }
      }))

      result = cli.parse(["--level", "bad"])
      result.valid?.should be_false
      result.errors.first.should eq("Invalid value for level: must be one of debug, info, warn")
    end
  end

  describe "defaults" do
    it "applies default values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string", "default": "anonymous"}
        }
      }))

      result = cli.parse([] of String)
      result["name"].as_s.should eq("anonymous")
    end

    it "does not override provided values with defaults" do
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "The user name"}
        },
        "required": ["name"]
      }))

      help = cli.help
      help.should contain("myapp")
      help.should contain("--name")
      help.should contain("required")
      help.should contain("The user name")
    end
  end

  describe "mixed styles" do
    it "accepts mixed argument styles" do
      cli = Jargon.cli("cat", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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
      cli = Jargon.cli("cli", json: %({
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

  describe "positional arguments" do
    it "parses positional args in order" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name", "count"],
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["John", "42"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
      result["count"].as_i64.should eq(42)
    end

    it "mixes positional and flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name", "count"],
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"},
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["John", "--verbose", "42"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
      result["count"].as_i64.should eq(42)
      result["verbose"].as_bool.should be_true
    end

    it "errors on unexpected positional args" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["John", "extra"])
      result.valid?.should be_false
      result.errors.should contain("Unexpected argument 'extra'")
    end

    it "validates required positional args" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      result = cli.parse([] of String)
      result.valid?.should be_false
      result.errors.should contain("Missing required field: name")
    end
  end

  describe "variadic positionals" do
    it "collects multiple arguments into array positional" do
      cli = Jargon.cli("cli", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array", "description": "Input files"}
        }
      }))

      result = cli.parse(["a.txt", "b.txt", "c.txt"])
      result.valid?.should be_true
      result["files"].as_a.map(&.as_s).should eq(["a.txt", "b.txt", "c.txt"])
    end

    it "handles flags mixed with variadic positionals" do
      cli = Jargon.cli("cat", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array"},
          "number": {"type": "boolean", "short": "n"}
        }
      }))

      result = cli.parse(["-n", "a.txt", "b.txt"])
      result.valid?.should be_true
      result["number"].as_bool.should be_true
      result["files"].as_a.map(&.as_s).should eq(["a.txt", "b.txt"])
    end

    it "handles non-array positional followed by array positional" do
      cli = Jargon.cli("cp", json: %q({
        "type": "object",
        "positional": ["dest", "sources"],
        "properties": {
          "dest": {"type": "string"},
          "sources": {"type": "array"}
        }
      }))

      result = cli.parse(["target/", "a.txt", "b.txt", "c.txt"])
      result.valid?.should be_true
      result["dest"].as_s.should eq("target/")
      result["sources"].as_a.map(&.as_s).should eq(["a.txt", "b.txt", "c.txt"])
    end

    it "returns empty array when no arguments for variadic" do
      cli = Jargon.cli("cat", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array"}
        }
      }))

      result = cli.parse([] of String)
      result.valid?.should be_true
      result["files"].as_a.should be_empty
    end

    it "stops collecting at flags (flags should come first)" do
      cli = Jargon.cli("cat", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array"},
          "number": {"type": "boolean", "short": "n"}
        }
      }))

      # Correct usage: flags first
      result = cli.parse(["-n", "a.txt", "b.txt", "c.txt"])
      result.valid?.should be_true
      result["number"].as_bool.should be_true
      result["files"].as_a.map(&.as_s).should eq(["a.txt", "b.txt", "c.txt"])

      # Incorrect usage: flag after positionals stops collection
      result2 = cli.parse(["a.txt", "-n", "b.txt"])
      result2.valid?.should be_false
      result2["files"].as_a.map(&.as_s).should eq(["a.txt"])
      result2["number"].as_bool.should be_true
      result2.errors.should contain("Unexpected argument 'b.txt'")
    end
  end

  describe "short flags" do
    it "parses short flags" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-n", "5"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(5)
    end

    it "parses short boolean flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"}
        }
      }))

      result = cli.parse(["-v"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
    end

    it "mixes short and long flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"},
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["-n", "5", "--verbose"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(5)
      result["verbose"].as_bool.should be_true
    end

    it "parses combined short boolean flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "verbose": {"type": "boolean", "short": "v"},
          "force": {"type": "boolean", "short": "f"}
        }
      }))

      result = cli.parse(["-avf"])
      result.valid?.should be_true
      result["all"].as_bool.should be_true
      result["verbose"].as_bool.should be_true
      result["force"].as_bool.should be_true
    end

    it "parses combined short flags with other args" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "verbose": {"type": "boolean", "short": "v"},
          "output": {"type": "string", "short": "o"}
        }
      }))

      result = cli.parse(["-av", "-o", "file.txt"])
      result.valid?.should be_true
      result["all"].as_bool.should be_true
      result["verbose"].as_bool.should be_true
      result["output"].as_s.should eq("file.txt")
    end

    it "errors on combined flags with non-boolean" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-an"])
      result.valid?.should be_false
      result.errors.first.should contain("Cannot combine non-boolean flag '-n'")
    end

    it "errors on combined flags with unknown flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "verbose": {"type": "boolean", "short": "v"}
        }
      }))

      result = cli.parse(["-avx"])
      result.valid?.should be_false
      result.errors.first.should contain("Unknown option '-x' in '-avx'")
    end

    it "errors on unknown short flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-x"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '-x'. Available: -n")
    end

    it "errors on unknown long flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["--unknown", "value"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '--unknown'. Available: --name, --count")
    end

    it "errors on unknown key=value style option" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["unknown=value"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option 'unknown'. Available: name")
    end
  end

  describe "typo suggestions" do
    it "suggests similar long flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"},
          "version": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--verbos"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '--verbos'. Did you mean '--verbose'?")
    end

    it "suggests similar options for key=value style" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "output": {"type": "string"},
          "format": {"type": "string"}
        }
      }))

      result = cli.parse(["outpt=file.txt"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option 'outpt'. Did you mean 'output'?")
    end

    it "does not suggest when distance is too large" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--xyz"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '--xyz'. Available: --verbose")
    end

    it "does not suggest for single-character flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"}
        }
      }))

      result = cli.parse(["-x"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '-x'. Available: -v")
    end
  end

  describe "subcommands" do
    it "parses subcommand with its options" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string"},
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["run", "test.cr", "--verbose"])
      result.valid?.should be_true
      result.subcommand.should eq("run")
      result["file"].as_s.should eq("test.cr")
      result["verbose"].as_bool.should be_true
    end

    it "errors on missing subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({"type": "object", "properties": {}}))

      result = cli.parse([] of String)
      result.valid?.should be_false
      result.errors.should contain("No subcommand specified")
    end

    it "errors on unknown subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["unknown"])
      result.valid?.should be_false
      result.errors.should contain("Unknown subcommand: unknown")
    end

    it "parses multiple subcommands independently" do
      cli = Jargon.new("xerp")
      cli.subcommand("index", json: %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["query_text"],
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10, "short": "n"}
        }
      }))

      result1 = cli.parse(["index", "--rebuild"])
      result1.valid?.should be_true
      result1.subcommand.should eq("index")
      result1["rebuild"].as_bool.should be_true

      result2 = cli.parse(["query", "retry backoff", "-n", "5"])
      result2.valid?.should be_true
      result2.subcommand.should eq("query")
      result2["query_text"].as_s.should eq("retry backoff")
      result2["top"].as_i64.should eq(5)
    end

    it "applies defaults in subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "top": {"type": "integer", "default": 10}
        }
      }))

      result = cli.parse(["query"])
      result.valid?.should be_true
      result["top"].as_i64.should eq(10)
    end

    it "validates required fields in subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("mark", json: %({
        "type": "object",
        "positional": ["result_id"],
        "properties": {
          "result_id": {"type": "string"}
        },
        "required": ["result_id"]
      }))

      result = cli.parse(["mark"])
      result.valid?.should be_false
      result.errors.should contain("Missing required field: result_id")
    end

    it "uses default subcommand when no subcommand given" do
      cli = Jargon.new("xerp")
      cli.subcommand("index", json: %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["query_text"],
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10, "short": "n"}
        }
      }))
      cli.default_subcommand("query")

      result = cli.parse(["retry backoff", "-n", "5"])
      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("retry backoff")
      result["top"].as_i64.should eq(5)
    end

    it "uses default subcommand with empty args" do
      cli = Jargon.new("myapp")
      cli.subcommand("list", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "default": false}
        }
      }))
      cli.default_subcommand("list")

      result = cli.parse([] of String)
      result.valid?.should be_true
      result.subcommand.should eq("list")
      result["all"].as_bool.should be_false
    end

    it "prefers explicit subcommand over default" do
      cli = Jargon.new("xerp")
      cli.subcommand("index", json: %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["query_text"],
        "properties": {
          "query_text": {"type": "string"}
        }
      }))
      cli.default_subcommand("query")

      result = cli.parse(["index", "--rebuild"])
      result.valid?.should be_true
      result.subcommand.should eq("index")
      result["rebuild"].as_bool.should be_true
    end

    it "loads subcommand from JSON file" do
      File.write("/tmp/test_subcmd.json", %({
        "type": "object",
        "properties": {
          "url": {"type": "string"}
        }
      }))
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("fetch", file: "/tmp/test_subcmd.json")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["url"].as_s.should eq("https://example.com")
      ensure
        File.delete("/tmp/test_subcmd.json")
      end
    end

    it "loads subcommand from YAML file" do
      File.write("/tmp/test_subcmd.yaml", <<-YAML)
        type: object
        properties:
          url:
            type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("fetch", file: "/tmp/test_subcmd.yaml")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["url"].as_s.should eq("https://example.com")
      ensure
        File.delete("/tmp/test_subcmd.yaml")
      end
    end

    it "loads multiple subcommands from multi-document YAML" do
      File.write("/tmp/test_multi.yaml", <<-YAML)
        ---
        name: fetch
        type: object
        properties:
          url:
            type: string
        ---
        name: save
        type: object
        properties:
          file:
            type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_multi.yaml")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["url"].as_s.should eq("https://example.com")

        result = cli.parse(["save", "--file", "output.txt"])
        result.valid?.should be_true
        result.subcommand.should eq("save")
        result["file"].as_s.should eq("output.txt")
      ensure
        File.delete("/tmp/test_multi.yaml")
      end
    end

    it "loads multiple subcommands from relaxed JSONL" do
      File.write("/tmp/test_multi.json", <<-JSON)
        {
          "name": "fetch",
          "type": "object",
          "properties": {
            "url": {"type": "string"}
          }
        }
        {
          "name": "save",
          "type": "object",
          "properties": {
            "file": {"type": "string"}
          }
        }
        JSON
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_multi.json")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")

        result = cli.parse(["save", "--file", "output.txt"])
        result.valid?.should be_true
        result.subcommand.should eq("save")
      ensure
        File.delete("/tmp/test_multi.json")
      end
    end

    it "Jargon.cli with file: auto-detects multi-doc YAML" do
      File.write("/tmp/test_subcmds.yaml", <<-YAML)
        ---
        name: run
        type: object
        properties:
          verbose:
            type: boolean
        ---
        name: build
        type: object
        properties:
          output:
            type: string
        YAML
      begin
        cli = Jargon.cli("myapp", file: "/tmp/test_subcmds.yaml")

        result = cli.parse(["run", "--verbose"])
        result.valid?.should be_true
        result.subcommand.should eq("run")
        result["verbose"].as_bool.should be_true

        result = cli.parse(["build", "--output", "dist/"])
        result.valid?.should be_true
        result.subcommand.should eq("build")
        result["output"].as_s.should eq("dist/")
      ensure
        File.delete("/tmp/test_subcmds.yaml")
      end
    end

    it "Jargon.cli with json: auto-detects multi-doc JSON" do
      json = <<-JSON
        {
          "name": "fetch",
          "type": "object",
          "properties": {"url": {"type": "string"}}
        }
        {
          "name": "save",
          "type": "object",
          "properties": {"file": {"type": "string"}}
        }
        JSON

      cli = Jargon.cli("myapp", json: json)

      result = cli.parse(["fetch", "--url", "https://example.com"])
      result.valid?.should be_true
      result.subcommand.should eq("fetch")

      result = cli.parse(["save", "--file", "out.txt"])
      result.valid?.should be_true
      result.subcommand.should eq("save")
    end

    it "Jargon.cli with yaml: auto-detects multi-doc YAML" do
      yaml = <<-YAML
        ---
        name: start
        type: object
        properties:
          port:
            type: integer
        ---
        name: stop
        type: object
        properties:
          force:
            type: boolean
        YAML

      cli = Jargon.cli("myapp", yaml: yaml)

      result = cli.parse(["start", "--port", "8080"])
      result.valid?.should be_true
      result.subcommand.should eq("start")
      result["port"].as_i64.should eq(8080)

      result = cli.parse(["stop", "--force"])
      result.valid?.should be_true
      result.subcommand.should eq("stop")
      result["force"].as_bool.should be_true
    end

    it "loads multi-doc as nested subcommands when name provided" do
      File.write("/tmp/test_nested_multi.yaml", <<-YAML)
        ---
        name: get
        type: object
        properties:
          key:
            type: string
        ---
        name: set
        type: object
        properties:
          key:
            type: string
          value:
            type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("config", file: "/tmp/test_nested_multi.yaml")

        result = cli.parse(["config", "get", "--key", "api_url"])
        result.valid?.should be_true
        result.subcommand.should eq("config get")
        result["key"].as_s.should eq("api_url")

        result = cli.parse(["config", "set", "--key", "api_url", "--value", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("config set")
        result["key"].as_s.should eq("api_url")
        result["value"].as_s.should eq("https://example.com")
      ensure
        File.delete("/tmp/test_nested_multi.yaml")
      end
    end

    it "supports $id mixins with $ref in allOf" do
      File.write("/tmp/test_mixin.yaml", <<-YAML)
        ---
        $id: global
        type: object
        properties:
          verbose:
            type: boolean
            short: v
          config:
            type: string
            short: c
        ---
        name: fetch
        allOf:
          - {$ref: global}
          - properties:
              url:
                type: string
        ---
        name: save
        allOf:
          - {$ref: global}
          - properties:
              file:
                type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_mixin.yaml")

        # fetch should have verbose, config, and url
        result = cli.parse(["fetch", "--verbose", "--config", "app.conf", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["verbose"].as_bool.should be_true
        result["config"].as_s.should eq("app.conf")
        result["url"].as_s.should eq("https://example.com")

        # save should have verbose, config, and file
        result = cli.parse(["save", "-v", "-c", "app.conf", "--file", "out.txt"])
        result.valid?.should be_true
        result.subcommand.should eq("save")
        result["verbose"].as_bool.should be_true
        result["config"].as_s.should eq("app.conf")
        result["file"].as_s.should eq("out.txt")
      ensure
        File.delete("/tmp/test_mixin.yaml")
      end
    end

    it "supports multiple $id mixins" do
      File.write("/tmp/test_multi_mixin.yaml", <<-YAML)
        ---
        $id: global
        properties:
          verbose:
            type: boolean
            short: v
        ---
        $id: output
        properties:
          format:
            type: string
            enum: [json, yaml, csv]
        ---
        name: export
        allOf:
          - {$ref: global}
          - {$ref: output}
          - properties:
              file:
                type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_multi_mixin.yaml")

        result = cli.parse(["export", "-v", "--format", "json", "--file", "out.txt"])
        result.valid?.should be_true
        result["verbose"].as_bool.should be_true
        result["format"].as_s.should eq("json")
        result["file"].as_s.should eq("out.txt")
      ensure
        File.delete("/tmp/test_multi_mixin.yaml")
      end
    end

    it "errors on unknown $ref" do
      File.write("/tmp/test_bad_ref.yaml", <<-YAML)
        ---
        $id: dummy
        properties:
          x: {type: string}
        ---
        name: fetch
        allOf:
          - {$ref: nonexistent}
          - properties:
              url:
                type: string
        YAML
      begin
        expect_raises(ArgumentError, /Unknown \$ref: nonexistent/) do
          cli = Jargon.new("myapp")
          cli.subcommand(file: "/tmp/test_bad_ref.yaml")
        end
      ensure
        File.delete("/tmp/test_bad_ref.yaml")
      end
    end

    it "errors when multi-doc schema missing both name and $id" do
      File.write("/tmp/test_no_name.yaml", <<-YAML)
        ---
        type: object
        properties:
          url:
            type: string
        ---
        name: save
        type: object
        properties:
          file:
            type: string
        YAML
      begin
        expect_raises(ArgumentError, /must have either 'name'.*or '\$id'/) do
          cli = Jargon.new("myapp")
          cli.subcommand(file: "/tmp/test_no_name.yaml")
        end
      ensure
        File.delete("/tmp/test_no_name.yaml")
      end
    end
  end

  describe "subcommand abbreviations" do
    it "matches unambiguous prefix" do
      cli = Jargon.new("myapp")
      cli.subcommand("checkout", json: %({"type": "object", "properties": {}}))
      cli.subcommand("commit", json: %({"type": "object", "properties": {}}))
      cli.subcommand("config", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["che"])
      result.valid?.should be_true
      result.subcommand.should eq("checkout")

      result = cli.parse(["comm"])
      result.valid?.should be_true
      result.subcommand.should eq("commit")

      result = cli.parse(["conf"])
      result.valid?.should be_true
      result.subcommand.should eq("config")
    end

    it "rejects abbreviations shorter than 3 characters" do
      cli = Jargon.new("myapp")
      cli.subcommand("checkout", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["ch"])
      result.valid?.should be_false
      result.errors.should contain("Unknown subcommand: ch")

      result = cli.parse(["c"])
      result.valid?.should be_false
    end

    it "rejects ambiguous abbreviations" do
      cli = Jargon.new("myapp")
      cli.subcommand("config-get", json: %({"type": "object", "properties": {}}))
      cli.subcommand("config-set", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["config-"])
      result.valid?.should be_false
      result.errors.should contain("Unknown subcommand: config-")
    end

    it "prefers exact match over prefix" do
      cli = Jargon.new("myapp")
      cli.subcommand("test", json: %({"type": "object", "properties": {}}))
      cli.subcommand("testing", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["test"])
      result.valid?.should be_true
      result.subcommand.should eq("test")
    end

    it "works with subcommand options" do
      cli = Jargon.new("git")
      cli.subcommand("checkout", json: %({
        "type": "object",
        "positional": ["branch"],
        "properties": {
          "branch": {"type": "string"}
        }
      }))

      result = cli.parse(["che", "main"])
      result.valid?.should be_true
      result.subcommand.should eq("checkout")
      result["branch"].as_s.should eq("main")
    end
  end

  describe "help with new features" do
    it "generates help with short flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n", "description": "Number of items"}
        }
      }))

      help = cli.help
      help.should contain("-n, --count")
      help.should contain("Number of items")
    end

    it "generates help with positional args" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string", "description": "Input file"},
          "verbose": {"type": "boolean"}
        }
      }))

      help = cli.help
      help.should contain("Arguments:")
      help.should contain("file")
      help.should contain("Input file")
    end

    it "generates help for subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({"type": "object", "properties": {}}))
      cli.subcommand("test", json: %({"type": "object", "properties": {}}))

      help = cli.help
      help.should contain("Commands:")
      help.should contain("run")
      help.should contain("test")
    end
  end

  describe "stdin JSON input" do
    it "parses JSON from stdin with subcommand in JSON" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10}
        },
        "required": ["query_text"]
      }))

      input = IO::Memory.new(%({"subcommand": "query", "query_text": "search term", "top": 5}))
      result = cli.parse(["-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("search term")
      result["top"].as_i64.should eq(5)
    end

    it "parses JSON from stdin for explicit subcommand" do
      cli = Jargon.new("xerp")
      cli.subcommand("mark", json: %({
        "type": "object",
        "properties": {
          "result_id": {"type": "string"},
          "useful": {"type": "boolean"}
        },
        "required": ["result_id"]
      }))

      input = IO::Memory.new(%({"result_id": "abc123", "useful": true}))
      result = cli.parse(["mark", "-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("mark")
      result["result_id"].as_s.should eq("abc123")
      result["useful"].as_bool.should be_true
    end

    it "uses default subcommand when not specified in JSON" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"}
        },
        "required": ["query_text"]
      }))
      cli.default_subcommand("query")

      input = IO::Memory.new(%({"query_text": "search term"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("search term")
    end

    it "applies defaults to JSON input" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10}
        }
      }))

      input = IO::Memory.new(%({"query_text": "test"}))
      result = cli.parse(["query", "-"], input)

      result.valid?.should be_true
      result["top"].as_i64.should eq(10)
    end

    it "validates JSON input" do
      cli = Jargon.new("xerp")
      cli.subcommand("mark", json: %({
        "type": "object",
        "properties": {
          "result_id": {"type": "string"}
        },
        "required": ["result_id"]
      }))

      input = IO::Memory.new(%({}))
      result = cli.parse(["mark", "-"], input)

      result.valid?.should be_false
      result.errors.should contain("Missing required field: result_id")
    end

    it "errors on invalid JSON" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))

      input = IO::Memory.new("not valid json")
      result = cli.parse(["query", "-"], input)

      result.valid?.should be_false
      result.errors.first.should contain("Invalid JSON")
    end

    it "errors when no subcommand in JSON and no default" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))

      input = IO::Memory.new(%({"foo": "bar"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_false
      result.errors.should contain("No 'subcommand' specified in JSON")
    end

    it "uses custom subcommand key" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"}
        }
      }))
      cli.subcommand_key("op")

      input = IO::Memory.new(%({"op": "query", "query_text": "search term"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("search term")
    end

    it "errors with custom key name in message" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))
      cli.subcommand_key("op")

      input = IO::Memory.new(%({"foo": "bar"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_false
      result.errors.should contain("No 'op' specified in JSON")
    end

    it "applies user defaults to stdin JSON input" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer"}
        }
      }))

      defaults = {"top" => JSON::Any.new(25_i64)}
      input = IO::Memory.new(%({"query_text": "search"}))
      result = cli.parse(["query", "-"], input, defaults: defaults)

      result.valid?.should be_true
      result["query_text"].as_s.should eq("search")
      result["top"].as_i64.should eq(25) # From defaults
    end

    it "applies env vars to stdin JSON input" do
      ENV["TEST_STDIN_HOST"] = "env-host"
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("run", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string", "env": "TEST_STDIN_HOST"},
            "port": {"type": "integer"}
          }
        }))

        input = IO::Memory.new(%({"port": 8080}))
        result = cli.parse(["run", "-"], input)

        result.valid?.should be_true
        result["host"].as_s.should eq("env-host") # From env var
        result["port"].as_i64.should eq(8080)
      ensure
        ENV.delete("TEST_STDIN_HOST")
      end
    end

    it "stdin JSON values override defaults and env vars" do
      ENV["TEST_STDIN_PORT"] = "9000"
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("run", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer", "env": "TEST_STDIN_PORT"}
          }
        }))

        defaults = {"host" => JSON::Any.new("default-host")}
        input = IO::Memory.new(%({"host": "json-host", "port": 3000}))
        result = cli.parse(["run", "-"], input, defaults: defaults)

        result.valid?.should be_true
        result["host"].as_s.should eq("json-host") # JSON wins over defaults
        result["port"].as_i64.should eq(3000)      # JSON wins over env var
      ensure
        ENV.delete("TEST_STDIN_PORT")
      end
    end
  end

  describe "nested subcommands" do
    it "parses nested subcommand" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "positional": ["name", "url"],
        "properties": {
          "name": {"type": "string"},
          "url": {"type": "string"}
        },
        "required": ["name", "url"]
      }))
      remote.subcommand("remove", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["remote", "add", "origin", "https://github.com/user/repo"])
      result.valid?.should be_true
      result.subcommand.should eq("remote add")
      result["name"].as_s.should eq("origin")
      result["url"].as_s.should eq("https://github.com/user/repo")
    end

    it "handles deeply nested subcommands" do
      level2 = Jargon.new("level2")
      level2.subcommand("action", json: %({
        "type": "object",
        "properties": {
          "flag": {"type": "boolean"}
        }
      }))

      level1 = Jargon.new("level1")
      level1.subcommand("level2", level2)

      cli = Jargon.new("app")
      cli.subcommand("level1", level1)

      result = cli.parse(["level1", "level2", "action", "--flag"])
      result.valid?.should be_true
      result.subcommand.should eq("level1 level2 action")
      result["flag"].as_bool.should be_true
    end

    it "mixes nested CLI and schema subcommands" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", json: %({"type": "object", "properties": {"short": {"type": "boolean", "short": "s"}}}))

      result1 = cli.parse(["remote", "add", "name=origin"])
      result1.valid?.should be_true
      result1.subcommand.should eq("remote add")

      result2 = cli.parse(["status", "-s"])
      result2.valid?.should be_true
      result2.subcommand.should eq("status")
      result2["short"].as_bool.should be_true
    end

    it "uses default subcommand in nested CLI" do
      remote = Jargon.new("remote")
      remote.subcommand("list", json: %({"type": "object", "properties": {"verbose": {"type": "boolean"}}}))
      remote.subcommand("add", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))
      remote.default_subcommand("list")

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      result = cli.parse(["remote", "--verbose"])
      result.valid?.should be_true
      result.subcommand.should eq("remote list")
      result["verbose"].as_bool.should be_true
    end

    it "validates nested subcommand data" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "properties": {"name": {"type": "string"}},
        "required": ["name"]
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      errors = cli.validate({"name" => JSON::Any.new("origin")}, "remote add")
      errors.should be_empty

      errors = cli.validate({} of String => JSON::Any, "remote add")
      errors.should contain("Missing required field: name")
    end

    it "shows nested commands in help" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({"type": "object", "properties": {}}))
      remote.subcommand("remove", json: %({"type": "object", "properties": {}}))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", json: %({"type": "object", "properties": {}}))

      help = cli.help
      help.should contain("remote")
      help.should contain("add")
      help.should contain("remove")
      help.should contain("status")
    end
  end

  describe "schema merge" do
    it "merges global properties into subcommand schema" do
      global = %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"},
          "config": {"type": "string", "short": "c"}
        }
      })

      sub = %({
        "type": "object",
        "properties": {
          "file": {"type": "string"}
        }
      })

      merged = Jargon.merge(sub, global)
      parsed = JSON.parse(merged)

      parsed["properties"]["file"].should_not be_nil
      parsed["properties"]["verbose"].should_not be_nil
      parsed["properties"]["config"].should_not be_nil
    end

    it "sub properties take precedence over global" do
      global = %({
        "type": "object",
        "properties": {
          "output": {"type": "string", "default": "stdout"}
        }
      })

      sub = %({
        "type": "object",
        "properties": {
          "output": {"type": "string", "default": "file.txt"}
        }
      })

      merged = Jargon.merge(sub, global)
      parsed = JSON.parse(merged)

      parsed["properties"]["output"]["default"].as_s.should eq("file.txt")
    end

    it "works with CLI parsing" do
      global = %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"}
        }
      })

      cli = Jargon.new("myapp")
      cli.subcommand("run", json: Jargon.merge(%({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string"}
        }
      }), global))

      result = cli.parse(["run", "test.cr", "-v"])
      result.valid?.should be_true
      result["file"].as_s.should eq("test.cr")
      result["verbose"].as_bool.should be_true
    end

    it "handles empty properties gracefully" do
      global = %({"type": "object", "properties": {"verbose": {"type": "boolean"}}})
      sub = %({"type": "object"})

      merged = Jargon.merge(sub, global)
      parsed = JSON.parse(merged)

      parsed["properties"]["verbose"].should_not be_nil
    end
  end

  describe "automatic help detection" do
    it "detects --help in flat schema" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects -h in flat schema" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "user-defined help property takes precedence" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "help": {"type": "string"}
        }
      }))

      result = cli.parse(["--help", "topic"])
      result.help_requested?.should be_false
      result["help"].as_s.should eq("topic")
    end

    it "user-defined -h short flag takes precedence" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "host": {"type": "string", "short": "h"}
        }
      }))

      result = cli.parse(["-h", "localhost"])
      result.help_requested?.should be_false
      result["host"].as_s.should eq("localhost")
    end

    it "detects top-level --help with subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects top-level -h with subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects subcommand help (query --help)" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["query", "--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("query")
    end

    it "detects subcommand help (query -h)" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["query", "-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("query")
    end

    it "detects nested subcommand help (remote add --help)" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "url": {"type": "string"}
        }
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      result = cli.parse(["remote", "add", "--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("remote add")
    end

    it "cli.help(subcommand) generates correct output" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["text"],
        "properties": {
          "text": {"type": "string", "description": "Search text"},
          "limit": {"type": "integer", "short": "n", "description": "Result limit"}
        },
        "required": ["text"]
      }))

      help = cli.help("query")
      help.should contain("Usage: myapp query")
      help.should contain("<text>")
      help.should contain("Search text")
      help.should contain("-n, --limit")
      help.should contain("Result limit")
    end

    it "cli.help(subcommand) works for nested subcommands" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string", "description": "Remote name"}
        },
        "required": ["name"]
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      help = cli.help("remote add")
      help.should contain("Usage: remote add")
      help.should contain("<name>")
      help.should contain("Remote name")
    end

    it "cli.help(subcommand) returns error for unknown subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))

      help = cli.help("unknown")
      help.should contain("Unknown subcommand: unknown")
    end

    it "help_requested is false when not requested" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["name=test"])
      result.help_requested?.should be_false
    end
  end

  describe "public validate method" do
    it "validates data hash directly" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"}
        },
        "required": ["name"]
      }))

      errors = cli.validate({"count" => JSON::Any.new(42_i64)})
      errors.should contain("Missing required field: name")
    end

    it "returns empty array for valid data" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      errors = cli.validate({"name" => JSON::Any.new("John")})
      errors.should be_empty
    end

    it "validates result object" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      result = cli.parse(["name=John"])
      errors = cli.validate(result)
      errors.should be_empty
    end

    it "validates subcommand data with subcommand name" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "properties": {
          "file": {"type": "string"}
        },
        "required": ["file"]
      }))

      errors = cli.validate({} of String => JSON::Any, "run")
      errors.should contain("Missing required field: file")
    end

    it "validates result from subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "properties": {
          "file": {"type": "string"}
        },
        "required": ["file"]
      }))

      result = cli.parse(["run", "file=test.cr"])
      errors = cli.validate(result)
      errors.should be_empty
    end
  end

  describe "shell completion" do
    describe "bash completion" do
      it "generates completion for flat CLI with flags" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string", "description": "User name"},
            "verbose": {"type": "boolean", "short": "v"}
          }
        }))

        bash = cli.bash_completion
        bash.should contain("_myapp_completions")
        bash.should contain("--name")
        bash.should contain("--verbose")
        bash.should contain("-v")
        bash.should contain("--help")
        bash.should contain("complete -F _myapp_completions myapp")
      end

      it "generates completion for CLI with subcommands" do
        cli = Jargon.new("myapp")
        cli.subcommand("fetch", json: %({
          "type": "object",
          "properties": {
            "url": {"type": "string"},
            "depth": {"type": "integer", "short": "d"}
          }
        }))
        cli.subcommand("save", json: %({
          "type": "object",
          "properties": {
            "file": {"type": "string"}
          }
        }))

        bash = cli.bash_completion
        bash.should contain("fetch")
        bash.should contain("save")
        bash.should contain("--url")
        bash.should contain("--depth")
        bash.should contain("-d")
        bash.should contain("--file")
      end

      it "generates enum completions" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "format": {"type": "string", "enum": ["json", "yaml", "xml"]}
          }
        }))

        bash = cli.bash_completion
        bash.should contain("--format")
        bash.should contain("json yaml xml")
      end

      it "generates completion for nested subcommands" do
        remote = Jargon.new("remote")
        remote.subcommand("add", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"},
            "url": {"type": "string"}
          }
        }))
        remote.subcommand("remove", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        cli = Jargon.new("git")
        cli.subcommand("remote", remote)

        bash = cli.bash_completion
        bash.should contain("remote")
        bash.should contain("add")
        bash.should contain("remove")
        bash.should contain("--name")
        bash.should contain("--url")
      end
    end

    describe "zsh completion" do
      it "generates completion for flat CLI with flags" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string", "description": "User name"},
            "verbose": {"type": "boolean", "short": "v"}
          }
        }))

        zsh = cli.zsh_completion
        zsh.should contain("#compdef myapp")
        zsh.should contain("_myapp")
        zsh.should contain("--name")
        zsh.should contain("--verbose")
        zsh.should contain("-v")
        zsh.should contain("User name")
      end

      it "generates completion for CLI with subcommands" do
        cli = Jargon.new("myapp")
        cli.subcommand("fetch", json: %({
          "type": "object",
          "properties": {
            "url": {"type": "string", "description": "Resource URL"},
            "depth": {"type": "integer", "short": "d", "description": "Crawl depth"}
          }
        }))

        zsh = cli.zsh_completion
        zsh.should contain("'fetch:")
        zsh.should contain("--url")
        zsh.should contain("Resource URL")
        zsh.should contain("{-d,--depth}")
        zsh.should contain("Crawl depth")
      end

      it "generates enum completions" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "format": {"type": "string", "enum": ["json", "yaml", "xml"]}
          }
        }))

        zsh = cli.zsh_completion
        zsh.should contain("--format")
        zsh.should contain("json yaml xml")
      end

      it "generates completion for nested subcommands" do
        remote = Jargon.new("remote")
        remote.subcommand("add", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        cli = Jargon.new("git")
        cli.subcommand("remote", remote)

        zsh = cli.zsh_completion
        zsh.should contain("'remote:")
        zsh.should contain("remote_commands")
        zsh.should contain("'add:")
      end
    end

    describe "fish completion" do
      it "generates completion for flat CLI with flags" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string", "description": "User name"},
            "verbose": {"type": "boolean", "short": "v", "description": "Verbose mode"}
          }
        }))

        fish = cli.fish_completion
        fish.should contain("complete -c myapp -f")
        fish.should contain("-l name")
        fish.should contain("-l verbose")
        fish.should contain("-s v")
        fish.should contain("User name")
        fish.should contain("Verbose mode")
      end

      it "generates completion for CLI with subcommands" do
        cli = Jargon.new("myapp")
        cli.subcommand("fetch", json: %({
          "type": "object",
          "properties": {
            "url": {"type": "string", "description": "Resource URL"},
            "depth": {"type": "integer", "short": "d"}
          }
        }))
        cli.subcommand("save", json: %({
          "type": "object",
          "properties": {
            "file": {"type": "string"}
          }
        }))

        fish = cli.fish_completion
        fish.should contain("__fish_use_subcommand")
        fish.should contain("-a \"fetch\"")
        fish.should contain("-a \"save\"")
        fish.should contain("__fish_seen_subcommand_from fetch")
        fish.should contain("-l url")
        fish.should contain("-l depth")
        fish.should contain("-s d")
        fish.should contain("-l file")
      end

      it "generates enum completions" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "format": {"type": "string", "enum": ["json", "yaml", "xml"]}
          }
        }))

        fish = cli.fish_completion
        fish.should contain("-l format")
        fish.should contain("-xa \"json yaml xml\"")
      end

      it "generates completion for nested subcommands" do
        remote = Jargon.new("remote")
        remote.subcommand("add", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string", "description": "Remote name"}
          }
        }))
        remote.subcommand("remove", json: %({
          "type": "object",
          "properties": {
            "force": {"type": "boolean", "short": "f"}
          }
        }))

        cli = Jargon.new("git")
        cli.subcommand("remote", remote)

        fish = cli.fish_completion
        fish.should contain("__fish_seen_subcommand_from remote")
        fish.should contain("-a \"add\"")
        fish.should contain("-a \"remove\"")
        fish.should contain("-l name")
        fish.should contain("Remote name")
        fish.should contain("-l force")
        fish.should contain("-s f")
      end
    end

    it "excludes positional arguments from flag completions" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string"},
          "verbose": {"type": "boolean", "short": "v"}
        }
      }))

      bash = cli.bash_completion
      bash.should contain("--verbose")
      bash.should_not contain("--file")

      zsh = cli.zsh_completion
      zsh.should contain("--verbose")
      zsh.should_not contain("--file")

      fish = cli.fish_completion
      fish.should contain("-l verbose")
      fish.should_not contain("-l file")
    end

    it "escapes shell metacharacters in bash completions" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "mode": {"type": "string", "enum": ["$HOME", "`whoami`", "test\\"quote"]}
        }
      }))

      bash = cli.bash_completion
      # Should escape $ to prevent variable expansion
      bash.should contain("\\$HOME")
      # Should escape backticks to prevent command substitution
      bash.should contain("\\`whoami\\`")
      # Should escape quotes
      bash.should contain("test\\\"quote")
    end

    it "handles numeric and boolean enum values in completions" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "level": {"type": "integer", "enum": [1, 2, 3]},
          "enabled": {"type": "boolean", "enum": [true, false]}
        }
      }))

      bash = cli.bash_completion
      bash.should contain("1 2 3")
      bash.should contain("true false")

      zsh = cli.zsh_completion
      zsh.should contain("1 2 3")
      zsh.should contain("true false")

      fish = cli.fish_completion
      fish.should contain("1 2 3")
      fish.should contain("true false")
    end

    describe "--completions flag" do
      it "detects --completions bash in flat CLI" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["--completions", "bash"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("bash")
      end

      it "detects --completions zsh in flat CLI" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["--completions", "zsh"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("zsh")
      end

      it "detects --completions fish in flat CLI" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["--completions", "fish"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("fish")
      end

      it "detects --completions in CLI with subcommands" do
        cli = Jargon.new("myapp")
        cli.subcommand("query", json: %({"type": "object", "properties": {}}))

        result = cli.parse(["--completions", "bash"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("bash")
      end

      it "errors on unknown shell" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {}
        }))

        result = cli.parse(["--completions", "powershell"])
        result.completion_requested?.should be_false
        result.valid?.should be_false
        result.errors.first.should contain("Unknown shell")
        result.errors.first.should contain("powershell")
      end

      it "completion_requested? is false when not requested" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["name=test"])
        result.completion_requested?.should be_false
        result.completion_shell.should be_nil
      end
    end
  end

  describe "load_config" do
    it "returns config_paths in correct order" do
      cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {}}))
      paths = cli.config_paths

      # Project local paths first (yaml, yml, json for each base)
      paths[0].should eq("./.config/myapp.yaml")
      paths[1].should eq("./.config/myapp.yml")
      paths[2].should eq("./.config/myapp.json")
      paths[3].should eq("./.config/myapp/config.yaml")
      paths[4].should eq("./.config/myapp/config.yml")
      paths[5].should eq("./.config/myapp/config.json")
      # User global paths
      paths[6].should contain("myapp.yaml")
      paths[9].should contain("myapp/config.yaml")
    end

    it "loads JSON config from project .config directory" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp.json", %({"host": "from-config", "port": 9000}))

      begin
        cli = Jargon.cli("testapp", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer"}
          }
        }))

        config = cli.load_config
        config.should_not be_nil
        config.not_nil!["host"].as_s.should eq("from-config")
        config.not_nil!["port"].as_i.should eq(9000)
      ensure
        File.delete("./.config/testapp.json")
      end
    end

    it "loads YAML config from project .config directory" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testyaml.yaml", "host: yaml-host\nport: 8080\ndebug: true")

      begin
        cli = Jargon.cli("testyaml", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer"},
            "debug": {"type": "boolean"}
          }
        }))

        config = cli.load_config
        config.should_not be_nil
        config.not_nil!["host"].as_s.should eq("yaml-host")
        config.not_nil!["port"].as_i.should eq(8080)
        config.not_nil!["debug"].as_bool.should be_true
      ensure
        File.delete("./.config/testyaml.yaml")
      end
    end

    it "prefers YAML over JSON when both exist" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testboth.yaml", "source: yaml")
      File.write("./.config/testboth.json", %({"source": "json"}))

      begin
        cli = Jargon.cli("testboth", json: %({
          "type": "object",
          "properties": {
            "source": {"type": "string"}
          }
        }))

        config = cli.load_config(merge: false)
        config.should_not be_nil
        config.not_nil!["source"].as_s.should eq("yaml")
      ensure
        File.delete("./.config/testboth.yaml")
        File.delete("./.config/testboth.json")
      end
    end

    it "returns nil when no config found" do
      cli = Jargon.cli("nonexistent-app-xyz", json: %({"type": "object", "properties": {}}))
      cli.load_config.should be_nil
    end

    it "integrates with defaults parameter" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp2.json", %({"verbose": true, "count": 5}))

      begin
        cli = Jargon.cli("testapp2", json: %({
          "type": "object",
          "properties": {
            "verbose": {"type": "boolean"},
            "count": {"type": "integer"}
          }
        }))

        config = cli.load_config
        result = cli.parse(["--count", "10"], defaults: config)

        result["verbose"].as_bool.should be_true # From config
        result["count"].as_i64.should eq(10)     # CLI overrides
      ensure
        File.delete("./.config/testapp2.json")
      end
    end

    it "merges configs with merge: true (project wins)" do
      xdg_config = ENV["XDG_CONFIG_HOME"]? || Path.home.join(".config").to_s

      # Create user config
      Dir.mkdir_p("#{xdg_config}/testapp3")
      File.write("#{xdg_config}/testapp3/config.json", %({"host": "user-host", "port": 8080, "user_only": "yes"}))

      # Create project config (should override user for shared keys)
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp3.json", %({"host": "project-host", "project_only": "yes"}))

      begin
        cli = Jargon.cli("testapp3", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer"},
            "user_only": {"type": "string"},
            "project_only": {"type": "string"}
          }
        }))

        config = cli.load_config(merge: true)
        config.should_not be_nil
        config.not_nil!["host"].as_s.should eq("project-host") # Project wins
        config.not_nil!["port"].as_i.should eq(8080)           # From user
        config.not_nil!["user_only"].as_s.should eq("yes")     # From user
        config.not_nil!["project_only"].as_s.should eq("yes")  # From project
      ensure
        File.delete("./.config/testapp3.json")
        File.delete("#{xdg_config}/testapp3/config.json")
        Dir.delete("#{xdg_config}/testapp3") rescue nil
      end
    end

    it "deep merges nested objects in configs" do
      xdg_config = ENV["XDG_CONFIG_HOME"]? || Path.home.join(".config").to_s

      # Create user config with nested object
      Dir.mkdir_p("#{xdg_config}/testapp4")
      File.write("#{xdg_config}/testapp4/config.json", %({
        "database": {"host": "localhost", "port": 5432, "user": "default_user"}
      }))

      # Create project config that overrides only some nested keys
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp4.json", %({
        "database": {"host": "production.example.com"}
      }))

      begin
        cli = Jargon.cli("testapp4", json: %({"type": "object", "properties": {}}))

        config = cli.load_config(merge: true)
        config.should_not be_nil
        db = config.not_nil!["database"]
        db["host"].as_s.should eq("production.example.com") # Project wins
        db["port"].as_i.should eq(5432)                     # Preserved from user
        db["user"].as_s.should eq("default_user")           # Preserved from user
      ensure
        File.delete("./.config/testapp4.json")
        File.delete("#{xdg_config}/testapp4/config.json")
        Dir.delete("#{xdg_config}/testapp4") rescue nil
      end
    end
  end

  describe "defaults parameter" do
    it "uses defaults when CLI arg not provided" do
      cli = Jargon.cli("testbad", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "verbose": {"type": "boolean"}
        }
      }))

      defaults = {"name" => JSON::Any.new("default-name"), "verbose" => JSON::Any.new(true)}
      result = cli.parse([] of String, defaults: defaults)

      result.valid?.should be_true
      result["name"].as_s.should eq("default-name")
      result["verbose"].as_bool.should be_true
    end

    it "CLI args override defaults" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      defaults = {"name" => JSON::Any.new("from-config")}
      result = cli.parse(["--name", "from-cli"], defaults: defaults)

      result["name"].as_s.should eq("from-cli")
    end

    it "works with JSON::Any from parsed JSON" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "output": {"type": "string"},
          "count": {"type": "integer"}
        }
      }))

      config_json = JSON.parse(%({"output": "default.txt", "count": 10}))
      result = cli.parse(["--count", "5"], defaults: config_json)

      result["output"].as_s.should eq("default.txt")
      result["count"].as_i64.should eq(5) # CLI overrides
    end

    it "schema defaults fill remaining gaps" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "host": {"type": "string", "default": "localhost"},
          "port": {"type": "integer", "default": 8080},
          "debug": {"type": "boolean"}
        }
      }))

      # User defaults override schema default for port
      # Schema default for host fills remaining gap
      defaults = {"port" => JSON::Any.new(3000_i64), "debug" => JSON::Any.new(true)}
      result = cli.parse([] of String, defaults: defaults)

      result["host"].as_s.should eq("localhost") # Schema default
      result["port"].as_i64.should eq(3000)      # User default
      result["debug"].as_bool.should be_true     # User default
    end

    it "works with subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "properties": {
          "env": {"type": "string"}
        }
      }))

      defaults = {"env" => JSON::Any.new("production")}
      result = cli.parse(["run"], defaults: defaults)

      result.subcommand.should eq("run")
      result["env"].as_s.should eq("production")
    end
  end

  describe "error handling edge cases" do
    it "handles invalid integer coercion with clear error" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["--count", "abc"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid integer value 'abc' for count")
    end

    it "handles invalid number coercion with clear error" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["--rate", "not-a-number"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid number value 'not-a-number' for rate")
    end

    it "rejects partial numeric values like '10x'" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"},
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["--count", "10x"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid integer value '10x' for count")

      result = cli.parse(["--rate", "3.14abc"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid number value '3.14abc' for rate")
    end

    it "errors on missing value for non-boolean flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"},
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--count"])
      result.valid?.should be_false
      result.errors.should contain("Missing value for --count")

      result = cli.parse(["--name"])
      result.valid?.should be_false
      result.errors.should contain("Missing value for --name")
    end

    it "errors on missing value for short non-boolean flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-n"])
      result.valid?.should be_false
      result.errors.should contain("Missing value for --count")
    end

    it "parses negative numbers as values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"},
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["--count", "-5"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(-5)

      result = cli.parse(["--rate", "-3.14"])
      result.valid?.should be_true
      result["rate"].as_f.should eq(-3.14)
    end

    it "handles malformed JSON config file gracefully" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testbad.json", "{ invalid json }")

      begin
        Jargon.config_warnings = false # Suppress warning during test
        cli = Jargon.cli("cli", json: %({"type": "object", "properties": {}}))
        # Returns nil and prints warning to STDERR (suppressed here)
        config = cli.load_config
        config.should be_nil
      ensure
        Jargon.config_warnings = true
        File.delete("./.config/testbad.json")
      end
    end

    it "handles malformed YAML config file gracefully" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testbadyaml.yaml", "invalid: yaml: content: [")

      begin
        Jargon.config_warnings = false # Suppress warning during test
        cli = Jargon.cli("testbadyaml", json: %({"type": "object", "properties": {}}))
        # Returns nil and prints warning to STDERR (suppressed here)
        config = cli.load_config
        config.should be_nil
      ensure
        Jargon.config_warnings = true
        File.delete("./.config/testbadyaml.yaml")
      end
    end
  end

  describe "nested object defaults" do
    it "applies defaults to nested objects" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "server": {
            "type": "object",
            "properties": {
              "host": {"type": "string", "default": "localhost"},
              "port": {"type": "integer", "default": 8080}
            }
          }
        }
      }))

      result = cli.parse(["server.host=example.com"])
      result.valid?.should be_true
      result["server"]["host"].as_s.should eq("example.com")
      result["server"]["port"].as_i64.should eq(8080) # Default applied
    end
  end

  describe "$ref edge cases" do
    it "handles missing $ref target gracefully" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "user": {"$ref": "#/$defs/nonexistent"}
        },
        "$defs": {}
      }))

      # Should not crash, just treat as unresolved
      result = cli.parse(["user.name=test"])
      result.valid?.should be_false
    end

    it "handles invalid $ref format gracefully" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "user": {"$ref": "invalid-ref-format"}
        }
      }))

      # Should not crash
      result = cli.parse([] of String)
      result.valid?.should be_true
    end
  end

  describe "environment variables" do
    it "uses env var when CLI arg not provided" do
      ENV["TEST_JARGON_HOST"] = "env-host"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string", "env": "TEST_JARGON_HOST"}
          }
        }))

        result = cli.parse([] of String)
        result["host"].as_s.should eq("env-host")
      ensure
        ENV.delete("TEST_JARGON_HOST")
      end
    end

    it "CLI args override env vars" do
      ENV["TEST_JARGON_PORT"] = "8080"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "port": {"type": "integer", "env": "TEST_JARGON_PORT"}
          }
        }))

        result = cli.parse(["--port", "3000"])
        result["port"].as_i64.should eq(3000)
      ensure
        ENV.delete("TEST_JARGON_PORT")
      end
    end

    it "env vars override config defaults" do
      ENV["TEST_JARGON_DEBUG"] = "true"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "debug": {"type": "boolean", "env": "TEST_JARGON_DEBUG"}
          }
        }))

        config = {"debug" => JSON::Any.new(false)}
        result = cli.parse([] of String, defaults: config)
        result["debug"].as_bool.should be_true
      ensure
        ENV.delete("TEST_JARGON_DEBUG")
      end
    end

    it "coerces env var values to correct types" do
      ENV["TEST_JARGON_COUNT"] = "42"
      ENV["TEST_JARGON_ENABLED"] = "true"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "count": {"type": "integer", "env": "TEST_JARGON_COUNT"},
            "enabled": {"type": "boolean", "env": "TEST_JARGON_ENABLED"}
          }
        }))

        result = cli.parse([] of String)
        result["count"].as_i64.should eq(42)
        result["enabled"].as_bool.should be_true
      ensure
        ENV.delete("TEST_JARGON_COUNT")
        ENV.delete("TEST_JARGON_ENABLED")
      end
    end

    it "ignores unset env vars" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "missing": {"type": "string", "env": "TEST_JARGON_NONEXISTENT_VAR"}
        }
      }))

      result = cli.parse([] of String)
      result["missing"]?.should be_nil
    end
  end
end
