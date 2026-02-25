# frozen_string_literal: true

require "lipgloss"
require "rouge"

module Rubyagents
  module UI
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    module Styles
      def self.label
        @label ||= Lipgloss::Style.new.faint(true)
      end

      def self.plan_label
        @plan_label ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#011627")
          .background("#FF9F1C")
          .padding(0, 1)
      end

      def self.plan_box
        @plan_box ||= Lipgloss::Style.new
          .border(:rounded)
          .border_foreground("#FF9F1C")
          .padding(0, 2)
      end

      def self.final_answer
        @final_answer ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#2EC4B6")
      end

      def self.error
        @error ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#FF0000")
      end

      def self.dim
        @dim ||= Lipgloss::Style.new.faint(true)
      end

      def self.spinner_style
        @spinner_style ||= Lipgloss::Style.new
          .foreground("#7B61FF")
      end
    end

    class Spinner
      def initialize(message)
        @message = message
        @running = false
        @frame = 0
      end

      def start
        @running = true
        @thread = Thread.new do
          while @running
            char = SPINNER_FRAMES[@frame % SPINNER_FRAMES.size]
            frame = Styles.spinner_style.render(char)
            $stderr.print "\r\e[K#{frame} #{@message}"
            @frame += 1
            sleep 0.08
          end
          $stderr.print "\r\e[K"
        end
      end

      def stop
        @running = false
        @thread&.join
      end
    end

    class << self
      def thought(text)
        puts Styles.label.render("Thought: ") + text
      end

      def code(source)
        puts
        highlighted = rouge_formatter.format(rouge_lexer.lex(source))
        highlighted.each_line { |line| puts "  #{line.rstrip}" }
        puts
      end

      def observation(text)
        puts Styles.label.render("Result: ") + truncate(text, 200)
      end

      def error(text)
        puts Styles.error.render("Error: ") + text
      end

      def plan(text)
        label = Styles.plan_label.render(" Plan ")
        body = Styles.plan_box.render(text)
        puts "\n#{label}\n#{body}\n"
      end

      def step_metrics(duration:, token_usage:)
        parts = []
        parts << format("%.1fs", duration) if duration > 0
        parts << token_usage.to_s if token_usage
        return if parts.empty?

        puts Styles.dim.render(parts.join(" | "))
        puts
      end

      def run_summary(total_steps:, total_duration:, total_tokens:)
        parts = ["#{total_steps} steps", format("%.1fs total", total_duration)]
        parts << total_tokens.to_s if total_tokens.total_tokens > 0
        puts Styles.dim.render(parts.join(" | "))
      end

      def final_answer(text)
        puts
        puts Styles.final_answer.render("Final answer: ") + text.to_s
      end

      def spinner(message)
        Spinner.new(message)
      end

      def welcome
        title = Lipgloss::Style.new
          .bold(true)
          .foreground("#7B61FF")
          .render("rubyagents")

        version = Styles.dim.render("v#{VERSION}")
        puts "#{title} #{version}"
        puts Styles.dim.render("Code-first AI agents for Ruby")
        puts
      end

      private

      def rouge_lexer
        @rouge_lexer ||= Rouge::Lexers::Ruby.new
      end

      def rouge_formatter
        @rouge_formatter ||= Rouge::Formatters::Terminal256.new(Rouge::Themes::Monokai.new)
      end

      def truncate(text, max)
        return text if text.length <= max
        text[0...max] + Styles.dim.render("... (truncated)")
      end

    end
  end
end
