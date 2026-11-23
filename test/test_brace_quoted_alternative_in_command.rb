# frozen_string_literal: true

require_relative 'test_helper'

# A quoted alternative inside braces expands in a command's arguments too
class TestBraceQuotedAlternativeInCommand < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_quoted_alternative_in_a_pipeline
    assert_equal "a\nb c\nd\ne f\n", run_shell(%q{printf '%s\n' {a,"b c"} {d,'e f'} | cat})
  end

  def test_quoted_alternative_on_the_fast_path
    repl = Rubish::REPL.new
    out = capture_stdout { repl.send(:execute, %q{echo {a,"b c"} {d,'e f'}}) }
    assert_equal "a b c d e f\n", out
  end
end
