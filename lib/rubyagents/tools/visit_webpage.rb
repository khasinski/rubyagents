# frozen_string_literal: true

require "net/http"
require "uri"
require "reverse_markdown"

module Rubyagents
  class VisitWebpage < Tool
    tool_name "visit_webpage"
    description "Fetches the content of a webpage and returns it as markdown"
    input :url, type: :string, description: "The URL of the webpage to visit"
    output_type :string

    def call(url:)
      uri = URI(url)
      uri = URI("https://#{url}") unless uri.scheme

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 15
      http.open_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
      request["Accept"] = "text/html"

      response = http.request(request)

      # Follow redirects (one level)
      if response.is_a?(Net::HTTPRedirection) && response["location"]
        return call(url: response["location"])
      end

      body = response.body
        .force_encoding("UTF-8")
        .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

      md = ReverseMarkdown.convert(body, unknown_tags: :bypass, github_flavored: true).strip
      md.empty? ? "No readable content found at #{url}" : md[0, 10_000]
    rescue => e
      "Error fetching #{url}: #{e.message}"
    end
  end
end
