# frozen_string_literal: true

require "lipgloss"
require "glamour"

module Rubyagents
  module UI
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    module Styles
      def self.thought
        @thought ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#FF9F1C")
      end

      def self.code_header
        @code_header ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#2EC4B6")
      end

      def self.observation
        @observation ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#E71D36")
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

      def self.final_answer_label
        @final_answer_label ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#011627")
          .background("#2EC4B6")
          .padding(0, 1)
      end

      def self.final_answer_box
        @final_answer_box ||= Lipgloss::Style.new
          .border(:rounded)
          .border_foreground("#2EC4B6")
          .padding(0, 2)
          .margin(1, 0)
          .width(76)
      end

      def self.error
        @error ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#FF0000")
      end

      def self.step_number
        @step_number ||= Lipgloss::Style.new
          .bold(true)
          .foreground("#7B61FF")
      end

      def self.dim
        @dim ||= Lipgloss::Style.new
          .faint(true)
      end

      def self.metrics
        @metrics ||= Lipgloss::Style.new
          .faint(true)
          .italic(true)
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
      def step_header(number, max_steps)
        puts Styles.step_number.render("━━━ Step #{number}/#{max_steps} ━━━")
      end

      def thought(text)
        puts Styles.thought.render("Thought: ") + text
      end

      def code(source)
        puts Styles.code_header.render("Code:")
        puts Glamour.render("```ruby\n#{source}\n```", style: "dark", width: 100)
      end

      def observation(text)
        puts Styles.observation.render("Observation: ") + truncate(text, 500)
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

        puts Styles.metrics.render("  #{parts.join(" | ")}")
      end

      def run_summary(total_steps:, total_duration:, total_tokens:)
        parts = ["#{total_steps} steps", format("%.1fs total", total_duration)]
        parts << total_tokens.to_s if total_tokens.total_tokens > 0
        puts Styles.dim.render("\n  #{parts.join(" | ")}")
      end

      def final_answer(text)
        label = Styles.final_answer_label.render(" Final Answer ")
        wrapped = word_wrap(text.to_s, 70)
        body = Styles.final_answer_box.render(wrapped)
        puts "\n#{label}\n#{body}"
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

      def truncate(text, max)
        return text if text.length <= max
        text[0...max] + Styles.dim.render("... (truncated)")
      end

      def word_wrap(text, width)
        text.split("\n").map do |line|
          if line.length <= width
            line
          else
            line.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").rstrip
          end
        end.join("\n")
      end
    end
  end
end
