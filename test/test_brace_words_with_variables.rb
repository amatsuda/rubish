# frozen_string_literal: true

require_relative 'test_helper'

# Variables in a word with braces expand after the braces do, as in bash
class TestBraceWordsWithVariables < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_builtin_arguments
    assert_equal "{1..3} 1a 1b a1 b1\n", run_shell('x=1; echo {$x..3} ${x}{a,b} {a,b}$x')
  end

  def test_external_command_arguments
    assert_equal "{1..3} 1a 1b a1 b1\n", run_shell('x=1; /bin/echo {$x..3} ${x}{a,b} {a,b}$x')
  end

  def test_for_list
    assert_equal "1a\n1b\n", run_shell('x=1; for w in ${x}{a,b}; do echo $w; done')
  end
end
