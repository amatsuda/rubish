# frozen_string_literal: true

require_relative 'test_helper'

# When reading the next command line keeps failing with EIO (the terminal
# was lost, or another process group owns it), the shell must not spin on
# the prompt forever; it tries to take the terminal back and otherwise
# exits like bash does on a dead terminal
class TestReplReadError < Test::Unit::TestCase
  class FailingFrontend
    def initialize(failures, lines = [])
      @failures = failures
      @lines = lines
    end

    def read_line(prompt:, rprompt: nil)
      if @failures.positive?
        @failures -= 1
        raise Errno::EIO
      end
      @lines.shift
    end

    def insert_text(_text); end
  end

  def setup
    @repl = Rubish::REPL.new
  end

  def run_prompt_loop(times)
    catch(:exit) do
      times.times { @repl.send(:process_line) }
      :still_looping
    end
  end

  def test_exits_with_a_message_after_repeated_read_errors
    @repl.instance_variable_set(:@frontend, FailingFrontend.new(100))
    status = nil
    err = capture_stderr { status = run_prompt_loop(10) }
    assert_not_equal :still_looping, status, 'the prompt loop must give up on a terminal that cannot be read'
    assert_match(/read error/, err)
  end

  def test_recovers_when_a_line_can_be_read_again
    Dir.mktmpdir('rubish_read_error') do |dir|
      out = File.join(dir, 'out.txt')
      @repl.instance_variable_set(:@frontend, FailingFrontend.new(2, ["echo recovered > #{out}", "echo again > #{out}"]))
      status = nil
      capture_stderr { status = run_prompt_loop(4) }
      assert_equal :still_looping, status
      assert_equal "again\n", File.read(out)
    end
  end
end
