# frozen_string_literal: true

require "stringio"

module Rubyagents
  class Sandbox
    DEFAULT_TIMEOUT = 30 # seconds

    attr_reader :timeout

    def initialize(tools:, timeout: DEFAULT_TIMEOUT)
      @tools = tools
      @timeout = timeout
      @tool_map = tools.each_with_object({}) { |t, h| h[t.class.tool_name] = t }
    end

    def execute(code)
      reader, writer = IO.pipe

      pid = Process.fork do
        reader.close
        result = run_in_child(code)
        Marshal.dump(result, writer)
      rescue => e
        Marshal.dump({ error: "#{e.class}: #{e.message}" }, writer)
      ensure
        writer.close
        exit!(0)
      end

      writer.close

      # Wait with timeout
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        if status
          break
        elsif Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          Process.kill("KILL", pid)
          Process.waitpid(pid)
          reader.close
          return { error: "Execution timed out after #{timeout}s" }
        end
        sleep 0.05
      end

      data = reader.read
      reader.close

      if data.empty?
        { output: "", result: nil, is_final_answer: false }
      else
        Marshal.load(data) # rubocop:disable Security/MarshalLoad
      end
    end

    private

    def run_in_child(code)
      # Capture stdout
      stdout_capture = StringIO.new
      $stdout = stdout_capture

      # Create a clean execution context with tool methods
      context = build_context

      result = context.instance_eval(code, "(agent)", 1)
      $stdout = STDOUT

      output = stdout_capture.string
      { output: output, result: result, is_final_answer: false }
    rescue FinalAnswerException => e
      $stdout = STDOUT
      output = stdout_capture.string
      { output: output, result: e.value, is_final_answer: true }
    end

    def build_context
      ctx = Object.new

      # Define each tool as a method on the context object
      @tool_map.each do |name, tool|
        if name == "final_answer"
          # Wrap final_answer to raise FinalAnswerException
          ctx.define_singleton_method(name) do |**kwargs|
            result = tool.call(**kwargs)
            raise FinalAnswerException.new(result)
          end
        else
          ctx.define_singleton_method(name) do |**kwargs|
            tool.call(**kwargs)
          end
        end
      end

      ctx
    end
  end
end
