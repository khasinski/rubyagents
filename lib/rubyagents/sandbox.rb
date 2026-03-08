# frozen_string_literal: true

require "stringio"

module Rubyagents
  class Sandbox
    DEFAULT_TIMEOUT = 30 # seconds

    # ---------------------------------------------------------------------------
    # Executor strategy — selected once at load time based on the Ruby engine.
    # Adding a new backend (e.g. TruffleRuby) is a new subclass + one constant.
    # ---------------------------------------------------------------------------
    class Executor
      def self.for_platform
        RUBY_ENGINE == "jruby" ? ThreadExecutor : ForkExecutor
      end

      def call(_timeout, &_block)
        raise NotImplementedError, "#{self.class}#call not implemented"
      end
    end

    # MRI / TruffleRuby: fork gives full process isolation and safe kill.
    class ForkExecutor < Executor
      def call(timeout, &block)
        reader, writer = IO.pipe

        pid = Process.fork do
          reader.close
          Marshal.dump(block.call, writer)
        rescue => e
          Marshal.dump({ error: "#{e.class}: #{e.message}" }, writer)
        ensure
          writer.close
          exit!(0)
        end

        writer.close

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

        data.empty? ? { output: "", result: nil, is_final_answer: false } : Marshal.load(data) # rubocop:disable Security/MarshalLoad
      end
    end

    # JRuby: fork is unavailable; use a thread with a join-based timeout.
    # STDOUT_MUTEX serializes $stdout redirection so concurrent sandbox calls
    # (e.g. managed agents) don't interleave captured output.
    class ThreadExecutor < Executor
      STDOUT_MUTEX = Mutex.new

      def call(timeout, &block)
        result = nil
        error  = nil

        thread = Thread.new do
          STDOUT_MUTEX.synchronize { result = block.call }
        rescue => e
          error = "#{e.class}: #{e.message}"
        end

        unless thread.join(timeout)
          thread.kill
          return { error: "Execution timed out after #{timeout}s" }
        end

        error ? { error: error } : result
      end
    end

    EXECUTOR = Executor.for_platform.new

    attr_reader :timeout

    def initialize(tools:, timeout: DEFAULT_TIMEOUT)
      @tools = tools
      @timeout = timeout
      @tool_map = tools.each_with_object({}) { |t, h| h[t.class.tool_name] = t }
    end

    def execute(code)
      EXECUTOR.call(@timeout) { run_in_child(code) }
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
