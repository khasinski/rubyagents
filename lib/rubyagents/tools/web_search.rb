# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "cgi"

module Rubyagents
  # NOTE: DuckDuckGo HTML scraping is fragile - selectors may break if DDG changes their markup.
  class WebSearch < Tool
    tool_name "web_search"
    description "Searches the web using DuckDuckGo and returns results"
    input :query, type: :string, description: "The search query"
    output_type :string

    def call(query:)
      uri = URI("https://html.duckduckgo.com/html/")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
      request.set_form_data(q: query)

      response = http.request(request)

      # Parse basic results from HTML
      results = response.body.scan(/<a rel="nofollow" class="result__a" href="(.*?)".*?>(.*?)<\/a>/m)
      snippets = response.body.scan(/<a class="result__snippet".*?>(.*?)<\/a>/m)

      output = results.first(5).each_with_index.map do |r, i|
        url = CGI.unescapeHTML(r[0])
        title = r[1].gsub(/<.*?>/, "").strip
        snippet = snippets[i] ? snippets[i][0].gsub(/<.*?>/, "").strip : ""
        "#{i + 1}. #{title}\n   #{url}\n   #{snippet}"
      end

      output.empty? ? "No results found for: #{query}" : output.join("\n\n")
    rescue => e
      "Search error: #{e.message}"
    end
  end
end
