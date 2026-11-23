# frozen_string_literal: true

require_relative 'test_helper'

# In an unquoted heredoc body, quotes are ordinary characters: only `$`,
# backticks and a backslash before `$`, backtick, backslash or newline are
# special
class TestHeredocQuotesLiteral < Test::Unit::TestCase
  def heredoc(body, prelude = '')
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', "#{prelude}cat <<X\n#{body}X\n"], &:read)
  end

  def test_double_quotes_stay
    assert_equal "\"q\" x \"y z\"\n", heredoc("\"q\" x \"y z\"\n")
  end

  def test_backslash_before_a_double_quote_stays
    assert_equal "\\\"e\\\"\n", heredoc("\\\"e\\\"\n")
  end

  def test_expansions_still_happen
    assert_equal "val \"val\" $ `\n", heredoc("$v \"$v\" \\$ \\`\n", 'v=val; ')
  end
end
