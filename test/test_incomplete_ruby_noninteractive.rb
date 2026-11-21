# frozen_string_literal: true

require_relative 'test_helper'
require 'timeout'

# A non-interactive shell (rubish -c, a script) has nothing to prompt for
# an unfinished Ruby expression: it is a syntax error at once, even when
# stdin is an open pipe with nothing on it
class TestIncompleteRubyNoninteractive < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_unfinished_lambda_does_not_wait_for_stdin
    reader, writer = IO.pipe
    original = $stdin.dup
    $stdin.reopen(reader)
    err = nil
    Timeout.timeout(5) { err = capture_stderr { execute('->') } }
    assert_match(/syntax error|unexpected/i, err)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  ensure
    $stdin.reopen(original)
    original.close
    writer.close
    reader.close
  end
end
