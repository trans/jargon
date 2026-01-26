require "./spec_helper"

describe Jargon do
  describe "basic parsing" do
    it "parses string values with equals style" do
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string", "default": "anonymous"}
        }
      }))

      result = cli.parse([] of String)
      result["name"].as_s.should eq("anonymous")
    end

    it "does not override provided values with defaults" do
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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

  describe "short flags" do
    it "parses short flags" do
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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

    it "errors on unknown short flag" do
      cli = Jargon.from_json(%({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-x"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '-x'. Available short flags: -n")
    end

    it "errors on unknown long flag" do
      cli = Jargon.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["--unknown", "value"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '--unknown'. Available options: --name, --count")
    end

    it "errors on unknown key=value style option" do
      cli = Jargon.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["unknown=value"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option 'unknown'. Available options: name")
    end
  end

  describe "subcommands" do
    it "parses subcommand with its options" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", %({
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
      cli.subcommand("run", %({"type": "object", "properties": {}}))

      result = cli.parse([] of String)
      result.valid?.should be_false
      result.errors.should contain("No subcommand specified")
    end

    it "errors on unknown subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", %({"type": "object", "properties": {}}))

      result = cli.parse(["unknown"])
      result.valid?.should be_false
      result.errors.should contain("Unknown subcommand: unknown")
    end

    it "parses multiple subcommands independently" do
      cli = Jargon.new("xerp")
      cli.subcommand("index", %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", %({
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
      cli.subcommand("query", %({
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
      cli.subcommand("mark", %({
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
      cli.subcommand("index", %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", %({
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
      cli.subcommand("list", %({
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
      cli.subcommand("index", %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", %({
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
  end

  describe "help with new features" do
    it "generates help with short flags" do
      cli = Jargon.from_json(%({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n", "description": "Number of items"}
        }
      }), "myapp")

      help = cli.help
      help.should contain("-n, --count")
      help.should contain("Number of items")
    end

    it "generates help with positional args" do
      cli = Jargon.from_json(%({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string", "description": "Input file"},
          "verbose": {"type": "boolean"}
        }
      }), "myapp")

      help = cli.help
      help.should contain("Arguments:")
      help.should contain("file")
      help.should contain("Input file")
    end

    it "generates help for subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", %({"type": "object", "properties": {}}))
      cli.subcommand("test", %({"type": "object", "properties": {}}))

      help = cli.help
      help.should contain("Commands:")
      help.should contain("run")
      help.should contain("test")
    end
  end

  describe "stdin JSON input" do
    it "parses JSON from stdin with subcommand in JSON" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", %({
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
      cli.subcommand("mark", %({
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
      cli.subcommand("query", %({
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
      cli.subcommand("query", %({
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
      cli.subcommand("mark", %({
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
      cli.subcommand("query", %({"type": "object", "properties": {}}))

      input = IO::Memory.new("not valid json")
      result = cli.parse(["query", "-"], input)

      result.valid?.should be_false
      result.errors.first.should contain("Invalid JSON")
    end

    it "errors when no subcommand in JSON and no default" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", %({"type": "object", "properties": {}}))

      input = IO::Memory.new(%({"foo": "bar"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_false
      result.errors.should contain("No 'subcommand' specified in JSON")
    end

    it "uses custom subcommand key" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", %({
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
      cli.subcommand("query", %({"type": "object", "properties": {}}))
      cli.subcommand_key("op")

      input = IO::Memory.new(%({"foo": "bar"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_false
      result.errors.should contain("No 'op' specified in JSON")
    end
  end

  describe "nested subcommands" do
    it "parses nested subcommand" do
      remote = Jargon.new("remote")
      remote.subcommand("add", %({
        "type": "object",
        "positional": ["name", "url"],
        "properties": {
          "name": {"type": "string"},
          "url": {"type": "string"}
        },
        "required": ["name", "url"]
      }))
      remote.subcommand("remove", %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", %({"type": "object", "properties": {}}))

      result = cli.parse(["remote", "add", "origin", "https://github.com/user/repo"])
      result.valid?.should be_true
      result.subcommand.should eq("remote add")
      result["name"].as_s.should eq("origin")
      result["url"].as_s.should eq("https://github.com/user/repo")
    end

    it "handles deeply nested subcommands" do
      level2 = Jargon.new("level2")
      level2.subcommand("action", %({
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
      remote.subcommand("add", %({"type": "object", "properties": {"name": {"type": "string"}}}))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", %({"type": "object", "properties": {"short": {"type": "boolean", "short": "s"}}}))

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
      remote.subcommand("list", %({"type": "object", "properties": {"verbose": {"type": "boolean"}}}))
      remote.subcommand("add", %({"type": "object", "properties": {"name": {"type": "string"}}}))
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
      remote.subcommand("add", %({
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
      remote.subcommand("add", %({"type": "object", "properties": {}}))
      remote.subcommand("remove", %({"type": "object", "properties": {}}))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", %({"type": "object", "properties": {}}))

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
      cli.subcommand("run", Jargon.merge(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli.subcommand("query", %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects top-level -h with subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects subcommand help (query --help)" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["query", "--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("query")
    end

    it "detects subcommand help (query -h)" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["query", "-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("query")
    end

    it "detects nested subcommand help (remote add --help)" do
      remote = Jargon.new("remote")
      remote.subcommand("add", %({
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
      cli.subcommand("query", %({
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
      remote.subcommand("add", %({
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
      cli.subcommand("query", %({"type": "object", "properties": {}}))

      help = cli.help("unknown")
      help.should contain("Unknown subcommand: unknown")
    end

    it "help_requested is false when not requested" do
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli = Jargon.from_json(%({
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
      cli.subcommand("run", %({
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
      cli.subcommand("run", %({
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
end
