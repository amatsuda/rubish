# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Inside backticks a backslash escapes `, \ and $, so `echo \`echo inner\``
# runs the inner substitution, and \$x reaches the inner shell as $x
class TestNestedBackticks < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_bt') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_escaped_backticks_nest_in_a_double_quoted_word
    assert_equal "nested inner\n", run_and_read('echo "`echo nested \`echo inner\``"')
  end

  def test_escaped_backticks_nest_in_a_bare_word
    assert_equal "nested inner\n", run_and_read('echo `echo nested \`echo inner\``')
  end

  def test_escaped_dollar_is_expanded_by_the_inner_command
    execute('bt_x=1')
    assert_equal "1\n", run_and_read('echo `echo \$bt_x`')
  end

  def test_lone_builtin_fast_path_also_nests
    execute('bt_y=`echo outer \`echo inner\``')
    assert_equal 'outer inner', get_shell_var('bt_y')
  end
end
