#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/rubyagents"

class StockPrice < Rubyagents::Tool
  tool_name "stock_price"
  description "Gets the current stock price for a ticker symbol"
  input :ticker, type: :string, description: "Stock ticker symbol (e.g. AAPL)"
  output_type :number

  def call(ticker:)
    # Simulated stock prices for demo
    prices = { "AAPL" => 182.52, "GOOGL" => 141.80, "TSLA" => 248.42, "RIVN" => 14.73 }
    prices.fetch(ticker.upcase, "Unknown ticker: #{ticker}")
  end
end

agent = Rubyagents::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  tools: [StockPrice]
)

agent.run("What's the difference in stock price between AAPL and TSLA?")
