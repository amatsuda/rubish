# frozen_string_literal: true

require_relative 'test_helper'

# $(cmd) whose body is a single side-effect-free builtin runs in-process
# instead of forking the interpreter, with the same results.
class TestSubstFastPath < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @context = @repl.instance_variable_get(:@context)
  end

  def teardown
    Rubish::Builtins.unset(%w[x])
    execute('unalias -a') rescue nil
    execute('unset -f echo') rescue nil
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  # Make fork fail loudly so the test proves the fast path was taken
  def without_fork
    @context.define_singleton_method(:fork) { |*| raise 'forked for a builtin substitution' }
    yield
  ensure
    @context.singleton_class.send(:remove_method, :fork)
  end

  def test_echo_substitution_runs_in_process
    result = without_fork { @context.__run_subst('echo hi there') }
    assert_equal 'hi there', result
  end

  def test_printf_substitution_runs_in_process
    assert_equal '007', without_fork { @context.__run_subst("printf '%03d' 7") }
  end

  def test_pwd_and_basename_run_in_process
    assert_equal Dir.pwd, without_fork { @context.__run_subst('pwd') }
    assert_equal 'b.txt', without_fork { @context.__run_subst('basename /a/b.txt') }
  end

  def test_trailing_newlines_are_stripped
    assert_equal 'a', without_fork { @context.__run_subst("printf 'a\\n\\n'") }
  end

  def test_status_of_fast_path_is_recorded
    without_fork { @context.__run_subst('false') }
    assert_equal 1, @context.last_status
    without_fork { @context.__run_subst('true') }
    assert_equal 0, @context.last_status
  end

  def test_variables_expand_inside_fast_path
    execute('x=world')
    assert_equal 'hello world', without_fork { @context.__run_subst('echo hello $x') }
  end

  def test_shell_level_behaviour_is_unchanged
    execute('x=$(echo nested $(echo inner))')
    assert_equal 'nested inner', get_shell_var('x')
  end

  def test_alias_is_honoured
    execute('shopt -s expand_aliases; alias echo="echo aliased"')
    execute('x=$(echo hi)')
    assert_equal 'aliased hi', get_shell_var('x')
  end

  def test_pipelines_and_externals_still_work
    execute('x=$(echo a | tr a b)')
    assert_equal 'b', get_shell_var('x')
    execute('x=$(/bin/echo ext)')
    assert_equal 'ext', get_shell_var('x')
  end

  def test_printf_v_is_not_taken_in_process_without_side_effect_loss
    execute('x=$(printf -v x_inner "%s" set; echo "$x_inner")')
    assert_equal 'set', get_shell_var('x')
    assert_nil get_shell_var('x_inner'), 'assignment inside $() must stay in the subshell'
  end
end
