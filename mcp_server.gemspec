Gem::Specification.new do |spec|
  spec.name = "mcp_server"
  spec.version = "0.1.0"
  spec.summary = "Pluggable, protocol-agnostic MCP server for Rack-based apps"
  spec.authors = ["Ajentik"]
  spec.email = ["engineering@ajentik.com"]
  spec.files = Dir["lib/**/*.rb"]
  spec.required_ruby_version = ">= 3.2.0"
  spec.homepage = "https://github.com/ajentik/ruby_mcp_server"
  spec.license = "MIT"

  spec.add_dependency "rack", ">= 2", "< 4"
  spec.add_dependency "mcp", "~> 0.1"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "standard", "~> 1.0"
end
