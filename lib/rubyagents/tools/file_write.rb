# frozen_string_literal: true

require "fileutils"

module Rubyagents
  class FileWrite < Tool
    tool_name "file_write"
    description "Writes content to a file at the given path, creating parent directories if needed"
    input :path, type: :string, description: "The path to the file to write"
    input :content, type: :string, description: "The content to write to the file"
    output_type :string

    def call(path:, content:)
      expanded = File.expand_path(path)
      FileUtils.mkdir_p(File.dirname(expanded))
      File.write(expanded, content)
      "Successfully wrote #{content.length} bytes to #{expanded}"
    rescue => e
      "Error writing #{path}: #{e.message}"
    end
  end
end
