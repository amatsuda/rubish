# frozen_string_literal: true

require_relative 'test_helper'

# An unquoted expansion in command position is split into words (bash)
class TestCommandNameFromUnquotedExpansion < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_words_from_a_variable
    assert_equal "hi there\n", run_shell("cmd='echo hi'; $cmd there")
  end

  def test_empty_expansion_leaves_the_next_word_as_the_command
    assert_equal "x\n0\n", run_shell('c=; $c echo x; e=; $e; echo $?')
  end

  def test_quoted_expansion_stays_one_word
    assert_match(/echo hi: command not found/, run_shell("cmd='echo hi'; \"$cmd\" 2>&1"))
  end
end
