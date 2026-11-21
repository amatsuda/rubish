# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# A line starting with a capitalised identifier is Ruby, except when it is a
# shell assignment: `Foo=bar; echo $Foo` must set the shell variable
class TestMixedCaseAssignment < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_mixed') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_mixed_case_assignment_followed_by_a_command_is_shell
    assert_equal "bar\n", run_and_read('MyVar=bar; echo $MyVar')
  end

  def test_mixed_case_lone_assignment_is_shell
    err = capture_stderr { execute('OtherVar=baz') }
    assert_equal '', err
    assert_equal 'baz', get_shell_var('OtherVar')
  end

  def test_ruby_constant_access_is_still_ruby
    out = capture_stdout { execute('Kernel.puts(1 + 1)') }
    assert_equal "2\n", out
  end

  def test_ruby_comparison_is_still_ruby
    out = capture_stdout { execute('Kernel.puts(Integer==Integer)') }
    assert_equal "true\n", out
  end
end
