# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# The result of an unquoted variable expansion is globbed, as in bash
class TestUnquotedVariableGlobbing < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @old = Dir.pwd
    @dir = Dir.mktmpdir
    Dir.chdir(@dir)
    FileUtils.touch(%w[f1.txt f2.txt])
  end

  def teardown
    Dir.chdir(@old)
    FileUtils.rm_rf(@dir)
  end

  def test_pattern_in_a_variable_expands
    out = capture_stdout { execute('x="*.txt"; echo $x; echo "$x"') }
    assert_equal "f1.txt f2.txt\n*.txt\n", out
  end

  def test_pattern_without_a_match_stays
    out = capture_stdout { execute('x="*.nomatch"; echo $x') }
    assert_equal "*.nomatch\n", out
  end
end
