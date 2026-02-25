# frozen_string_literal: true

module Rubyagents
  class FileRead < Tool
    tool_name "file_read"
    description "Reads the contents of a file at the given path and returns it as text"
    input :path, type: :string, description: "The path to the file to read"
    output_type :string

    MAX_CHARS = 50_000

    def call(path:)
      expanded = File.expand_path(path)
      content = File.read(expanded)
      content.length > MAX_CHARS ? content[0, MAX_CHARS] : content
    rescue => e
      "Error reading #{path}: #{e.message}"
    end
  end
end
