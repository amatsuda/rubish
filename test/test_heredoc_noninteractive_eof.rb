# frozen_string_literal: true

require_relative 'test_helper'
require 'timeout'

# A non-interactive shell whose input is not a terminal has no more lines to
# offer a heredoc that the command line itself does not close: the body is
# empty and a warning says so, as in bash. It must never prompt for it.
class TestHeredocNoninteractiveEof < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_unterminated_heredoc_gets_an_empty_body_without_waiting
    reader, writer = IO.pipe
    original = $stdin.dup
    $stdin.reopen(reader)
    out = err = nil
    Timeout.timeout(5) { err = capture_stderr { out = capture_stdout { execute('cat <<EOF') } } }
    assert_equal '', out
    assert_match(/here-document.*delimited by end-of-file/, err)
  ensure
    $stdin.reopen(original)
    original.close
    writer.close
    reader.close
  end
end
