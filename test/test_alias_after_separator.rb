# frozen_string_literal: true

require_relative 'test_helper'

# Aliases expand at every command position of a line, not only the first word
class TestAliasAfterSeparator < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_after_semicolon_and_operators
    assert_equal "one\ntwo\nthree\nfour\n", run_shell(%q{shopt -s expand_aliases; alias e='echo'; eval 'e one; e two && e three | cat; true || e no; e four'})
  end

  def test_not_in_arguments_or_quotes
    assert_equal "e e\n", run_shell(%q{shopt -s expand_aliases; alias e='echo'; eval "e e 'e'"})
  end

  def test_after_keywords
    assert_equal "yes\n", run_shell(%q{shopt -s expand_aliases; alias e='echo'; eval 'if true; then e yes; fi'})
  end
end
