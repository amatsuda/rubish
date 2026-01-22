# frozen_string_literal: true

require_relative 'test_helper'

class TestGetopts < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    Rubish::Builtins.reset_getopts
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def test_simple_option
    result = Rubish::Builtins.run('getopts', ['abc', 'opt', '-a'])
    assert result
    assert_equal 'a', get_shell_var('opt')
  end

  def test_multiple_options_separate
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b'])
    assert_equal 'a', get_shell_var('opt')
    assert_equal '2', get_shell_var('OPTIND')

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b'])
    assert_equal 'b', get_shell_var('opt')
    assert_equal '3', get_shell_var('OPTIND')
  end

  def test_grouped_options
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-abc'])
    assert_equal 'a', get_shell_var('opt')

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-abc'])
    assert_equal 'b', get_shell_var('opt')

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-abc'])
    assert_equal 'c', get_shell_var('opt')
  end

  def test_option_with_argument_separate
    result = Rubish::Builtins.run('getopts', ['a:bc', 'opt', '-a', 'value'])
    assert result
    assert_equal 'a', get_shell_var('opt')
    assert_equal 'value', get_shell_var('OPTARG')
    assert_equal '3', get_shell_var('OPTIND')
  end

  def test_option_with_argument_attached
    result = Rubish::Builtins.run('getopts', ['a:bc', 'opt', '-avalue'])
    assert result
    assert_equal 'a', get_shell_var('opt')
    assert_equal 'value', get_shell_var('OPTARG')
    assert_equal '2', get_shell_var('OPTIND')
  end

  def test_invalid_option
    output = capture_output do
      Rubish::Builtins.run('getopts', ['abc', 'opt', '-x'])
    end
    assert_equal '?', get_shell_var('opt')
    assert_match(/illegal option/, output)
  end

  def test_invalid_option_silent
    output = capture_output do
      Rubish::Builtins.run('getopts', [':abc', 'opt', '-x'])
    end
    assert_equal '?', get_shell_var('opt')
    assert_equal 'x', get_shell_var('OPTARG')
    assert_equal '', output  # Silent mode
  end

  def test_missing_argument
    output = capture_output do
      Rubish::Builtins.run('getopts', ['a:', 'opt', '-a'])
    end
    assert_equal '?', get_shell_var('opt')
    assert_match(/requires an argument/, output)
  end

  def test_missing_argument_silent
    output = capture_output do
      Rubish::Builtins.run('getopts', [':a:', 'opt', '-a'])
    end
    assert_equal ':', get_shell_var('opt')
    assert_equal 'a', get_shell_var('OPTARG')
    assert_equal '', output  # Silent mode
  end

  def test_end_of_options
    result = Rubish::Builtins.run('getopts', ['abc', 'opt', 'nonoption'])
    assert_false result
    assert_equal '?', get_shell_var('opt')
  end

  def test_double_dash_ends_options
    Rubish::Builtins.run('getopts', ['abc', 'opt', '--', '-a'])
    assert_equal '?', get_shell_var('opt')
  end

  def test_single_dash_is_not_option
    result = Rubish::Builtins.run('getopts', ['abc', 'opt', '-'])
    assert_false result
    assert_equal '?', get_shell_var('opt')
  end

  def test_optind_advances
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b', '-c'])
    assert_equal '2', get_shell_var('OPTIND')

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b', '-c'])
    assert_equal '3', get_shell_var('OPTIND')

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b', '-c'])
    assert_equal '4', get_shell_var('OPTIND')
  end

  def test_no_more_options
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a'])
    result = Rubish::Builtins.run('getopts', ['abc', 'opt', '-a'])
    assert_false result
  end

  def test_usage_error
    output = capture_output do
      result = Rubish::Builtins.run('getopts', ['abc'])
    end
    assert_match(/usage/, output)
  end

  def test_reset_getopts
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b'])
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b'])
    assert_equal '3', get_shell_var('OPTIND')

    Rubish::Builtins.reset_getopts
    assert_equal '1', get_shell_var('OPTIND')
  end

  def test_optarg_cleared_for_no_arg_option
    Rubish::Builtins.run('getopts', ['a:b', 'opt', '-a', 'value', '-b'])
    assert_equal 'value', get_shell_var('OPTARG')

    Rubish::Builtins.run('getopts', ['a:b', 'opt', '-a', 'value', '-b'])
    assert_nil get_shell_var('OPTARG')
  end

  # OPTERR tests

  def test_opterr_default_shows_errors
    # OPTERR defaults to showing errors (any value except '0')
    ENV.delete('OPTERR')
    output = capture_output do
      Rubish::Builtins.run('getopts', ['abc', 'opt', '-x'])
    end
    assert_match(/illegal option/, output)
  end

  def test_opterr_1_shows_errors
    ENV['OPTERR'] = '1'
    output = capture_output do
      Rubish::Builtins.run('getopts', ['abc', 'opt', '-x'])
    end
    assert_match(/illegal option/, output)
  end

  def test_opterr_0_suppresses_invalid_option_error
    ENV['OPTERR'] = '0'
    output = capture_output do
      Rubish::Builtins.run('getopts', ['abc', 'opt', '-x'])
    end
    assert_equal '?', get_shell_var('opt')
    assert_equal '', output  # Error suppressed
  end

  def test_opterr_0_suppresses_missing_argument_error
    ENV['OPTERR'] = '0'
    output = capture_output do
      Rubish::Builtins.run('getopts', ['a:', 'opt', '-a'])
    end
    assert_equal '?', get_shell_var('opt')
    assert_equal '', output  # Error suppressed
  end

  def test_opterr_0_does_not_set_optarg_for_invalid_option
    # Unlike silent mode (: prefix), OPTERR=0 doesn't set OPTARG
    ENV['OPTERR'] = '0'
    ENV.delete('OPTARG')
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-x'])
    assert_equal '?', get_shell_var('opt')
    assert_nil get_shell_var('OPTARG')  # Not set (unlike silent mode)
  end

  def test_opterr_0_does_not_affect_missing_arg_behavior
    # Unlike silent mode (: prefix), OPTERR=0 sets opt to '?' not ':'
    ENV['OPTERR'] = '0'
    Rubish::Builtins.run('getopts', ['a:', 'opt', '-a'])
    assert_equal '?', get_shell_var('opt')  # '?' not ':'
    assert_nil get_shell_var('OPTARG')  # Not set (unlike silent mode)
  end

  def test_silent_mode_overrides_opterr
    # Silent mode from ':' prefix works regardless of OPTERR
    ENV['OPTERR'] = '1'
    output = capture_output do
      Rubish::Builtins.run('getopts', [':abc', 'opt', '-x'])
    end
    assert_equal '?', get_shell_var('opt')
    assert_equal 'x', get_shell_var('OPTARG')  # Silent mode sets OPTARG
    assert_equal '', output  # Silent mode suppresses errors
  end
end
