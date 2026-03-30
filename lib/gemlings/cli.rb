# frozen_string_literal: true

require "optparse"

module Gemlings
  class CLI
    TOOL_MAP = {
      "web_search" => -> { require_relative "tools/web_search"; WebSearch },
      "visit_webpage" => -> { require_relative "tools/visit_webpage"; VisitWebpage },
      "user_input" => -> { require_relative "tools/user_input"; UserInput },
      "file_read" => -> { require_relative "tools/file_read"; FileRead },
      "file_write" => -> { require_relative "tools/file_write"; FileWrite }
    }.freeze

    def self.run(argv = ARGV)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv
      @options = {
        model: "openai/gpt-5.2",
        tools: [],
        mcp: [],
        interactive: false,
        stream: false,
        max_steps: 10,
        planning_interval: nil,
        agent_type: "code",
        executor: nil
      }
      parse_options!
    end

    def run
      if @options[:interactive]
        interactive_mode
      elsif @query
        single_query(@query)
      else
        puts @parser.help
      end
    end

    private

    def parse_options!
      @parser = OptionParser.new do |opts|
        opts.banner = "Usage: gemlings [options] \"query\""
        opts.separator ""

        opts.on("-m", "--model MODEL", "Model to use (default: openai/gpt-5.2)") do |m|
          @options[:model] = m
        end

        opts.on("-t", "--tools TOOLS", "Comma-separated tool names (#{TOOL_MAP.keys.join(", ")})") do |t|
          @options[:tools] = t.split(",").map(&:strip)
        end

        opts.on("-a", "--agent-type TYPE", "Agent type: code or tool_calling (default: code)") do |a|
          @options[:agent_type] = a
        end

        opts.on("-p", "--plan N", Integer, "Re-plan every N steps") do |n|
          @options[:planning_interval] = n
        end

        opts.on("-i", "--interactive", "Interactive mode") do
          @options[:interactive] = true
        end

        opts.on("-S", "--stream", "Stream LLM tokens to the terminal") do
          @options[:stream] = true
        end

        opts.on("--mcp COMMAND", "MCP server command (repeatable)") do |cmd|
          @options[:mcp] << cmd
        end

        opts.on("-s", "--max-steps N", Integer, "Max agent steps (default: 10)") do |n|
          @options[:max_steps] = n
        end

        opts.on("-e", "--executor NAME", "Sandbox executor: fork, thread, box (default: auto)") do |e|
          @options[:executor] = e.to_sym
        end

        opts.on("-v", "--version", "Show version") do
          puts "gemlings #{VERSION}"
          exit
        end

        opts.on("-h", "--help", "Show help") do
          puts opts
          exit
        end
      end

      @parser.parse!(@argv)
      @query = @argv.join(" ") unless @argv.empty?
    end

    def build_agent
      tools = @options[:tools].filter_map do |name|
        loader = TOOL_MAP[name]
        if loader
          loader.call
        else
          $stderr.puts "Unknown tool: #{name}. Available: #{TOOL_MAP.keys.join(", ")}"
          nil
        end
      end

      @options[:mcp].each do |cmd|
        mcp_tools = Gemlings.tools_from_mcp(command: cmd)
        tools.concat(mcp_tools)
      end

      agent_class = @options[:agent_type] == "tool_calling" ? ToolCallingAgent : CodeAgent

      opts = {
        model: @options[:model],
        tools: tools,
        max_steps: @options[:max_steps],
        planning_interval: @options[:planning_interval]
      }
      opts[:executor] = @options[:executor] if @options[:executor] && agent_class == CodeAgent
      agent_class.new(**opts)
    end

    def single_query(query)
      UI.welcome
      agent = build_agent
      agent.run(query, stream: @options[:stream])
    end

    def interactive_mode
      UI.welcome
      puts "Type your queries (Ctrl+C to exit)\n\n"

      agent = build_agent
      first = true

      loop do
        prompt = LIPGLOSS_AVAILABLE ? Lipgloss::Style.new.bold(true).foreground("#7B61FF").render(">> ") : ">> "
        print prompt
        query = $stdin.gets&.strip
        break if query.nil? || query.empty?

        agent.run(query, reset: first, stream: @options[:stream])
        first = false
        puts
      end
    rescue Interrupt
      puts "\nGoodbye!"
    end
  end
end
