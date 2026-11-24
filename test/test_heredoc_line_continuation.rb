# frozen_string_literal: true

require_relative 'test_helper'

# A backslash-newline in an unquoted heredoc body joins the lines, as in bash
class TestHeredocLineContinuation < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_unquoted_body_joins_lines
    assert_equal "line continued\n", run_shell("cat <<EOF\nline \\\ncontinued\nEOF\n")
  end

  def test_quoted_body_keeps_the_backslash
    assert_equal "line \\\nnot continued\n", run_shell("cat <<'EOF'\nline \\\nnot continued\nEOF\n")
  end
end
