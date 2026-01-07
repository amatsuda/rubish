# frozen_string_literal: true

require_relative 'test_helper'

class TestInheritErrexit < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_set_options = Rubish::Builtins.set_options.dup
    @tempdir = Dir.mktmpdir('rubish_inherit_errexit_test')
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.set_options.clear
    @original_set_options.each { |k, v| Rubish::Builtins.set_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # inherit_errexit is disabled by default
  def test_inherit_errexit_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('inherit_errexit')
  end

  def test_inherit_errexit_can_be_enabled
    execute('shopt -s inherit_errexit')
    assert Rubish::Builtins.shopt_enabled?('inherit_errexit')
  end

  def test_inherit_errexit_can_be_disabled
    execute('shopt -s inherit_errexit')
    execute('shopt -u inherit_errexit')
    assert_false Rubish::Builtins.shopt_enabled?('inherit_errexit')
  end

  # Without inherit_errexit: command substitution runs all commands even after failure
  def test_command_substitution_without_inherit_errexit
    # Create a script that should run completely without inherit_errexit
    execute('x=$(false; echo after)')
    # Without inherit_errexit, 'echo after' should run even after false fails
    assert_equal 'after', ENV['x']
  end

  # With inherit_errexit + errexit: command substitution stops at first failure
  def test_command_substitution_with_inherit_errexit
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute('x=$(false; echo after)')
    # With inherit_errexit and errexit, 'false' causes exit before 'echo after'
    assert_equal '', ENV['x']
  end

  # Backtick substitution also respects inherit_errexit
  def test_backtick_substitution_with_inherit_errexit
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute('x=`false; echo after`')
    # With inherit_errexit and errexit, 'false' causes exit before 'echo after'
    assert_equal '', ENV['x']
  end

  # Without errexit, inherit_errexit has no effect
  def test_inherit_errexit_without_errexit
    execute('shopt -s inherit_errexit')
    # errexit is not set

    execute('x=$(false; echo after)')
    # Without errexit, inherit_errexit has no effect - all commands run
    assert_equal 'after', ENV['x']
  end

  # Multiple commands in substitution with inherit_errexit
  def test_multiple_commands_with_inherit_errexit
    execute('shopt -s inherit_errexit')
    execute('set -e')

    # First command succeeds, second fails, third should not run
    execute('x=$(echo first; false; echo third)')
    assert_equal 'first', ENV['x']
  end

  # Successful command substitution with inherit_errexit
  def test_successful_substitution_with_inherit_errexit
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute('x=$(echo hello)')
    assert_equal 'hello', ENV['x']
  end

  # Nested command substitution with inherit_errexit
  def test_nested_substitution_with_inherit_errexit
    execute('shopt -s inherit_errexit')
    execute('set -e')

    # Inner substitution fails, outer should get empty result
    execute('x=$(echo $(false; echo inner))')
    assert_equal '', ENV['x']
  end

  # Command substitution with failing command
  def test_substitution_with_failing_command
    execute('shopt -s inherit_errexit')
    execute('set -e')

    # With inherit_errexit and errexit, false causes empty output
    execute('x=$(false)')
    assert_equal '', ENV['x']
  end

  # Command substitution with successful command
  def test_substitution_with_successful_command
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute('x=$(true; echo done)')
    assert_equal 'done', ENV['x']
  end

  # Command substitution in echo with inherit_errexit
  def test_substitution_in_echo_with_inherit_errexit
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute("echo $(echo hello) > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # Command substitution with pipeline inside
  def test_substitution_with_pipeline_inherit_errexit
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute('x=$(echo hello | tr a-z A-Z)')
    assert_equal 'HELLO', ENV['x']
  end

  # Verify that disabling inherit_errexit restores default behavior
  def test_disable_inherit_errexit_restores_default
    execute('shopt -s inherit_errexit')
    execute('set -e')
    execute('shopt -u inherit_errexit')

    # With inherit_errexit disabled, even with errexit, substitution doesn't inherit it
    execute('x=$(false; echo after)')
    assert_equal 'after', ENV['x']
  end

  # Test with $(...) syntax specifically
  def test_dollar_paren_syntax
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute('x=$(false; echo should_not_appear)')
    assert_equal '', ENV['x']
  end

  # Test with complex command that fails mid-stream
  def test_complex_failing_command
    execute('shopt -s inherit_errexit')
    execute('set -e')

    # With inherit_errexit, exit 42 stops execution before echo end
    execute('x=$(echo start; exit 42; echo end)')
    assert_equal 'start', ENV['x']
  end

  # Test that regular commands still work
  def test_regular_commands_unaffected
    execute('shopt -s inherit_errexit')
    execute('set -e')

    execute("echo hello > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end
end
