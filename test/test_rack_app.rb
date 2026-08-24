require "test_helper"
require "rack/mock"
require "mcp"

class TestRackApp < Minitest::Test
  def setup
    McpServer.configuration = McpServer::Configuration.new
    McpServer.configuration.transport = MCP::Server::Transports::StreamableHTTPTransport
  end

  def app
    McpServer::RackApp
  end

  def test_allows_get_method
    request = Rack::MockRequest.new(app)
    response = request.get("/")

    assert_equal 400, response.status
    body = JSON.parse(response.body)
    assert_equal "Missing session ID", body["error"]
  end

  def test_allows_put_method
    request = Rack::MockRequest.new(app)
    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 1
    }.to_json

    response = request.put("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 405, response.status
    body = JSON.parse(response.body)
    assert_equal "Method not allowed", body["error"]
  end

  def test_handles_empty_body_gracefully
    request = Rack::MockRequest.new(app)
    response = request.post("/", input: "")

    assert_equal 400, response.status
    body = JSON.parse(response.body)
    assert_equal "Invalid JSON", body["error"]
  end

  def test_handles_different_content_types
    request = Rack::MockRequest.new(app)
    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 2
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "text/plain")

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal "2.0", body["jsonrpc"]
    assert_equal 2, body["id"]
  end

  def test_patch_method_works
    request = Rack::MockRequest.new(app)
    mcp_request = {
      jsonrpc: "2.0",
      method: "initialize",
      params: {},
      id: 3
    }.to_json

    response = request.patch("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 405, response.status
    body = JSON.parse(response.body)
    assert_equal "Method not allowed", body["error"]
  end

  def test_context_includes_request_method
    context_received = nil

    test_tool_class = Class.new(MCP::Tool) do
      tool_name "method_test"
      description "Test tool to verify request method in context"

      define_singleton_method(:call) do |server_context:|
        context_received = server_context
        MCP::Tool::Response.new(
          content: [MCP::Content.text("Method received")]
        )
      end
    end

    McpServer.configure do |config|
      config.tools = -> { [test_tool_class] }
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    tool_call = {
      jsonrpc: "2.0",
      method: "tools/call",
      params: {
        name: "method_test",
        arguments: {}
      },
      id: 4
    }

    response = request.post("/",
      :input => tool_call.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    assert context_received[:request], "Context should include request"
    assert_equal "POST", context_received[:request].request_method
  end

  def test_authentication_failure
    McpServer.configure do |config|
      config.authenticate_with = lambda { |_request| false }
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 1
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 401, response.status
    body = JSON.parse(response.body)
    assert_equal "Unauthorized", body["error"]
  end

  def test_mcp_initialization_request
    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "initialize",
      params: {
        protocolVersion: "0.1.0",
        capabilities: {},
        clientInfo: {
          name: "test_client",
          version: "1.0.0"
        }
      },
      id: 1
    }

    response = request.post("/",
      :input => mcp_request.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)

    assert_equal "2.0", body["jsonrpc"]
    assert_equal 1, body["id"]
    assert body["result"]
    assert_equal "mcp_server", body["result"]["serverInfo"]["name"]
    assert_equal "0.1.0", body["result"]["serverInfo"]["version"]
  end

  def test_mcp_ping_request
    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 2
    }

    response = request.post("/",
      :input => mcp_request.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)

    assert_equal "2.0", body["jsonrpc"]
    assert_equal 2, body["id"]
    assert_equal({}, body["result"])
  end

  def test_with_custom_tool
    test_tool_class = Class.new(MCP::Tool) do
      tool_name "test_tool"
      description "A test tool"
      input_schema(
        properties: {
          message: {type: "string"}
        },
        required: ["message"]
      )

      def self.call(message:)
        MCP::Tool::Response.new(
          content: [
            MCP::Content.text("Echo: #{message}")
          ]
        )
      end
    end

    McpServer.configure do |config|
      config.tools = -> { [test_tool_class] }
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    list_request = {
      jsonrpc: "2.0",
      method: "tools/list",
      params: {},
      id: 3
    }

    response = request.post("/",
      :input => list_request.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)

    assert body["result"], "Expected 'result' in response"
    assert body["result"]["tools"], "Expected 'tools' in result"
    assert_equal 1, body["result"]["tools"].length
    assert_equal "test_tool", body["result"]["tools"][0]["name"]
  end

  def test_server_context_with_custom_context
    test_user = Struct.new(:id, :name).new(123, "Test User")
    context_received = nil

    test_tool_class = Class.new(MCP::Tool) do
      tool_name "context_test"
      description "Test tool to verify context"

      define_singleton_method(:call) do |server_context:|
        context_received = server_context
        MCP::Tool::Response.new(
          content: [MCP::Content.text("Context received")]
        )
      end
    end

    McpServer.configure do |config|
      config.build_context_with = lambda { |_request|
        {
          user: test_user,
          organization: {id: 456, name: "Test Org"},
          permissions: ["read", "write"],
          custom_data: "test"
        }
      }
      config.tools = -> { [test_tool_class] }
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    tool_call = {
      jsonrpc: "2.0",
      method: "tools/call",
      params: {
        name: "context_test",
        arguments: {}
      },
      id: 4
    }

    response = request.post("/",
      :input => tool_call.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status

    assert context_received[:request], "Context should include request"
    assert_equal test_user, context_received[:user]
    assert_equal({id: 456, name: "Test Org"}, context_received[:organization])
    assert_equal(["read", "write"], context_received[:permissions])
    assert_equal "test", context_received[:custom_data]
  end

  def test_with_custom_prompt
    test_prompt_class = Class.new(MCP::Prompt) do
      def self.name_value
        "test_prompt"
      end

      def self.description_value
        "A test prompt"
      end

      def self.arguments_value
        [
          MCP::Prompt::Argument.new(
            name: "topic",
            description: "The topic to generate a prompt for",
            required: true
          )
        ]
      end

      def self.template(args, server_context:)
        MCP::Prompt::Result.new(
          messages: [
            MCP::Prompt::Message.new(
              role: "user",
              content: MCP::Content.text("Tell me about #{args[:topic]}")
            )
          ]
        )
      end
    end

    McpServer.configure do |config|
      config.prompts = -> { [test_prompt_class] }
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    list_request = {
      jsonrpc: "2.0",
      method: "prompts/list",
      params: {},
      id: 5
    }

    response = request.post("/",
      :input => list_request.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)

    assert body["result"], "Expected 'result' in response"
    assert body["result"]["prompts"], "Expected 'prompts' in result"
    assert_equal 1, body["result"]["prompts"].length
    assert_equal "test_prompt", body["result"]["prompts"][0]["name"]
  end

  def test_with_custom_resource
    test_resource = MCP::Resource.new(
      uri: "test://resource1",
      name: "Test Resource",
      description: "A test resource",
      mime_type: "text/plain"
    )

    McpServer.configure do |config|
      config.resources = -> { [test_resource] }
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    list_request = {
      jsonrpc: "2.0",
      method: "resources/list",
      params: {},
      id: 6
    }

    response = request.post("/",
      :input => list_request.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)

    assert body["result"], "Expected 'result' in response"
    assert body["result"]["resources"], "Expected 'resources' in result"
    assert_equal 1, body["result"]["resources"].length
    assert_equal "test://resource1", body["result"]["resources"][0]["uri"]
    assert_equal "Test Resource", body["result"]["resources"][0]["name"]
  end

  def test_with_resources_read_handler
    test_resource = MCP::Resource.new(
      uri: "test://resource1",
      name: "Test Resource",
      description: "A test resource",
      mime_type: "text/plain"
    )

    read_handler = lambda do |params|
      [{
        uri: params[:uri],
        mimeType: "text/plain",
        text: "Resource content for #{params[:uri]}"
      }]
    end

    McpServer.configure do |config|
      config.resources = -> { [test_resource] }
      config.resources_read_handler = read_handler
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    read_request = {
      jsonrpc: "2.0",
      method: "resources/read",
      params: {
        uri: "test://resource1"
      },
      id: 8
    }

    response = request.post("/",
      :input => read_request.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal "2.0", body["jsonrpc"]
    assert_equal 8, body["id"]
    assert body["result"]["contents"]
    assert_equal 1, body["result"]["contents"].length
    assert_equal "test://resource1", body["result"]["contents"][0]["uri"]
    assert_equal "Resource content for test://resource1", body["result"]["contents"][0]["text"]
  end

  def test_with_transport_configuration
    transport_class = Class.new do
      attr_reader :server

      def initialize(server)
        @server = server
      end

      def handle_request(request)
        [200, {"Content-Type" => "application/json"}, [{jsonrpc: "2.0", id: 7, result: {test: true}}.to_json]]
      end
    end

    McpServer.configure do |config|
      config.transport = transport_class
    end

    request = Rack::MockRequest.new(McpServer::RackApp)

    mcp_request = {
      jsonrpc: "2.0",
      method: "initialize",
      params: {},
      id: 7
    }

    response = request.post("/",
      :input => mcp_request.to_json,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal "2.0", body["jsonrpc"]
    assert_equal 7, body["id"]
  end

  def test_error_handling
    request = Rack::MockRequest.new(app)

    response = request.post("/",
      :input => "invalid json",
      "CONTENT_TYPE" => "application/json")

    assert_equal 400, response.status
    body = JSON.parse(response.body)
    assert_equal "Invalid JSON", body["error"]
  end

  def test_authentication_success_with_custom_logic
    authenticated_user = nil

    McpServer.configure do |config|
      config.authenticate_with = lambda { |request|
        token = request.env["HTTP_AUTHORIZATION"]
        if token == "Bearer valid_token"
          authenticated_user = {id: 123, name: "Test User"}
          true
        else
          false
        end
      }
    end

    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 1
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 401, response.status

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer valid_token")

    assert_equal 200, response.status
    assert_equal({id: 123, name: "Test User"}, authenticated_user)
  end

  def test_response_handler_modifies_response
    response_handler_called = false

    McpServer.configure do |config|
      config.response_handler = lambda { |response, request|
        response_handler_called = true

        status, headers, body = response
        headers["X-Custom-Header"] = "Modified"
        headers["X-Request-Path"] = request.path

        if body.is_a?(Array) && body.first
          modified_body = JSON.parse(body.first)
          modified_body["custom_wrapper"] = true
          body = [modified_body.to_json]
        end

        [status, headers, body]
      }
    end

    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 2
    }.to_json

    response = request.post("/test-path",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    assert response_handler_called
    assert_equal "Modified", response.headers["X-Custom-Header"]
    assert_equal "/test-path", response.headers["X-Request-Path"]

    body = JSON.parse(response.body)
    assert body["custom_wrapper"]
    assert_equal "2.0", body["jsonrpc"]
  end

  def test_transport_error_handling
    error_transport = Class.new do
      def initialize(server)
        @server = server
      end

      def handle_request(request)
        raise StandardError, "Transport error occurred"
      end
    end

    McpServer.configure do |config|
      config.transport = error_transport
    end

    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 4
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 500, response.status
    body = JSON.parse(response.body)
    assert_match(/Transport error occurred/, body["error"])
  end

  def test_transport_body_response_types
    nil_body_transport = Class.new do
      def initialize(server)
        @server = server
      end

      def handle_request(request)
        [200, {"Content-Type" => "application/json"}, nil]
      end
    end

    McpServer.configure do |config|
      config.transport = nil_body_transport
    end

    request = Rack::MockRequest.new(app)
    response = request.post("/", input: '{"jsonrpc":"2.0","method":"ping","id":5}')

    assert_equal 200, response.status
    assert_equal "", response.body

    string_body_transport = Class.new do
      def initialize(server)
        @server = server
      end

      def handle_request(request)
        [200, {"Content-Type" => "application/json"}, '{"result":"string body"}']
      end
    end

    McpServer.configure do |config|
      config.transport = string_body_transport
    end

    response = request.post("/", input: '{"jsonrpc":"2.0","method":"ping","id":6}')
    assert_equal 200, response.status
    assert_equal '{"result":"string body"}', response.body

    array_body_transport = Class.new do
      def initialize(server)
        @server = server
      end

      def handle_request(request)
        [200, {"Content-Type" => "application/json"}, ['{"part1":"a"}', nil, '{"part2":"b"}']]
      end
    end

    McpServer.configure do |config|
      config.transport = array_body_transport
    end

    response = request.post("/", input: '{"jsonrpc":"2.0","method":"ping","id":7}')
    assert_equal 200, response.status
    assert_equal '{"part1":"a"}{"part2":"b"}', response.body

    object_body_transport = Class.new do
      def initialize(server)
        @server = server
      end

      def handle_request(request)
        [200, {"Content-Type" => "application/json"}, {result: "object body"}]
      end
    end

    McpServer.configure do |config|
      config.transport = object_body_transport
    end

    response = request.post("/", input: '{"jsonrpc":"2.0","method":"ping","id":8}')
    assert_equal 200, response.status
    assert_equal '{"result":"object body"}', response.body
  end

  def test_legacy_mcp_server_compatibility
    legacy_transport = Class.new do
      def initialize(server)
        @server = server
      end
    end

    McpServer.configure do |config|
      config.transport = legacy_transport
    end

    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 9
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status

    body_string = JSON.parse(response.body)
    body = JSON.parse(body_string)

    assert_equal "2.0", body["jsonrpc"]
    assert_equal 9, body["id"]
    assert_equal({}, body["result"])
  end

  def test_response_handler_returns_nil
    McpServer.configure do |config|
      config.response_handler = lambda { |response, request|
      }
    end

    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 10
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal "2.0", body["jsonrpc"]
    assert_equal 10, body["id"]
  end

  def test_build_context_with_non_hash_return
    context_received = nil

    test_tool_class = Class.new(MCP::Tool) do
      tool_name "context_check"
      description "Check context contents"

      define_singleton_method(:call) do |server_context:|
        context_received = server_context
        MCP::Tool::Response.new(
          content: [MCP::Content.text("Context checked")]
        )
      end
    end

    McpServer.configure do |config|
      config.build_context_with = lambda { |request|
        "not a hash"
      }
      config.tools = -> { [test_tool_class] }
    end

    request = Rack::MockRequest.new(app)

    tool_call = {
      jsonrpc: "2.0",
      method: "tools/call",
      params: {
        name: "context_check",
        arguments: {}
      },
      id: 11
    }.to_json

    response = request.post("/",
      :input => tool_call,
      "CONTENT_TYPE" => "application/json")

    assert_equal 200, response.status
    assert context_received[:request]
    assert_equal 1, context_received.keys.length
  end

  def test_request_body_rewind
    rewindable_body = StringIO.new('{"jsonrpc":"2.0","method":"ping","id":12}')
    rewind_count = 0

    rewindable_body.define_singleton_method(:rewind) do
      rewind_count += 1
      seek(0)
    end

    legacy_transport = Class.new do
      def initialize(server)
        @server = server
      end
    end

    McpServer.configure do |config|
      config.transport = legacy_transport
    end

    env = {
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/",
      "rack.input" => rewindable_body,
      "CONTENT_TYPE" => "application/json"
    }

    response = app.call(env)

    assert_equal 200, response[0]
    assert_equal 1, rewind_count, "Body should be rewound once"
  end

  def test_no_transport_configured
    McpServer.configure do |config|
      config.transport = nil
    end

    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "ping",
      params: {},
      id: 13
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 500, response.status
    body = JSON.parse(response.body)
    assert_equal "Internal server error", body["error"]
  end

  def test_transport_nomethoderror_returns_500_not_legacy_fallback
    nomethoderror_transport = Class.new do
      def initialize(server)
        @server = server
      end

      def handle_request(request)
        raise NoMethodError, "undefined method `boom' for nil"
      end
    end

    McpServer.configure do |config|
      config.tools = -> { [] }
      config.transport = nomethoderror_transport
    end

    request = Rack::MockRequest.new(app)

    mcp_request = {
      jsonrpc: "2.0",
      method: "tools/list",
      params: {},
      id: 1
    }.to_json

    response = request.post("/",
      :input => mcp_request,
      "CONTENT_TYPE" => "application/json")

    assert_equal 500, response.status
    body = JSON.parse(response.body)
    assert_match(/Internal server error/, body["error"])
  end
end
