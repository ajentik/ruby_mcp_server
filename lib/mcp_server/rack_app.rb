require "json"
require "rack"
require "mcp"

module McpServer
  class RackApp
    class << self
      def call(env)
        request = Rack::Request.new(env)
        config = McpServer.configuration

        if config.authenticate_with && !config.authenticate_with.call(request)
          return [401, {"Content-Type" => "application/json"}, [{error: "Unauthorized"}.to_json]]
        end

        server_context = build_server_context(request, config)

        mcp_server = MCP::Server.new(
          name: "mcp_server",
          version: "0.1.0",
          tools: config.tools&.call || [],
          prompts: config.prompts&.call || [],
          resources: config.resources&.call || [],
          server_context: server_context
        )

        if config.resources_read_handler
          mcp_server.resources_read_handler(&config.resources_read_handler)
        end

        response = nil
        if config.transport
          begin
            mcp_server.transport = config.transport.new(mcp_server)

            if mcp_server.transport.respond_to?(:handle_request)
              status, headers, body = mcp_server.transport.handle_request(request)

              body = if body.nil?
                []
              elsif body.is_a?(String)
                [body]
              elsif body.is_a?(Array)
                body.compact
              elsif body.is_a?(Hash)
                [body.to_json]
              else
                [body.to_s]
              end

              response = [status, headers, body]
            else
              # mcp <= 0.1.0 / transports without handle_request: no transport
              # dispatch support; process the raw JSON-RPC body directly.
              request.body.rewind if request.body.respond_to?(:rewind)
              json_response = mcp_server.handle_json(request.body.read)
              response = [200, {"Content-Type" => "application/json"}, [json_response.to_json]]
            end
          rescue => e
            Rails.logger.error("MCP RackApp: Error - #{e.class}: #{e.message}") if defined?(Rails)
            response = [500, {"Content-Type" => "application/json"}, [{error: "Internal server error: #{e.message}"}.to_json]]
          end
        end

        # Ensure response is never nil
        response ||= [500, {"Content-Type" => "application/json"}, [{error: "Internal server error"}.to_json]]

        if config.response_handler
          handled_response = config.response_handler.call(response, request)
          response = handled_response if handled_response
        end

        response
      end

      private

      def build_server_context(request, config)
        context = {request: request}

        if config.build_context_with
          custom_context = config.build_context_with.call(request)
          context.merge!(custom_context) if custom_context.is_a?(Hash)
        end

        context
      end
    end
  end
end
