# frozen_string_literal: true

require_relative "lib/rubyagents/version"

Gem::Specification.new do |spec|
  spec.name = "rubyagents"
  spec.version = Rubyagents::VERSION
  spec.authors = ["Chris Hasiński"]
  spec.email = ["krzysztof.hasinski@gmail.com"]

  spec.summary = "A radically simple, code-first AI agent framework for Ruby"
  spec.description = "Agents that write and execute Ruby code. Inspired by smolagents. " \
                     "LLMs write executable code, not JSON blobs."
  spec.homepage = "https://github.com/khasinski/rubyagents"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?("spec/", "test/", ".git", ".github", "Gemfile")
    end
  end

  spec.bindir = "exe"
  spec.executables = ["rubyagents"]
  spec.require_paths = ["lib"]

  spec.add_dependency "lipgloss", "~> 0.2" unless RUBY_ENGINE == "jruby"
  spec.add_dependency "reverse_markdown", "~> 3.0"
  spec.add_dependency "rouge", "~> 4.0"
  spec.add_dependency "json-schema", "~> 4.0"
  spec.add_dependency "bigdecimal"
  spec.add_dependency "mcp", "~> 0.7"
  spec.add_dependency "ruby_llm", "~> 1.1"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
end
