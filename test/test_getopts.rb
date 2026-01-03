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
    assert_equal 'a', ENV['opt']
  end

  def test_multiple_options_separate
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b'])
    assert_equal 'a', ENV['opt']
    assert_equal '2', ENV['OPTIND']

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b'])
    assert_equal 'b', ENV['opt']
    assert_equal '3', ENV['OPTIND']
  end

  def test_grouped_options
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-abc'])
    assert_equal 'a', ENV['opt']

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-abc'])
    assert_equal 'b', ENV['opt']

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-abc'])
    assert_equal 'c', ENV['opt']
  end

  def test_option_with_argument_separate
    result = Rubish::Builtins.run('getopts', ['a:bc', 'opt', '-a', 'value'])
    assert result
    assert_equal 'a', ENV['opt']
    assert_equal 'value', ENV['OPTARG']
    assert_equal '3', ENV['OPTIND']
  end

  def test_option_with_argument_attached
    result = Rubish::Builtins.run('getopts', ['a:bc', 'opt', '-avalue'])
    assert result
    assert_equal 'a', ENV['opt']
    assert_equal 'value', ENV['OPTARG']
    assert_equal '2', ENV['OPTIND']
  end

  def test_invalid_option
    output = capture_output do
      Rubish::Builtins.run('getopts', ['abc', 'opt', '-x'])
    end
    assert_equal '?', ENV['opt']
    assert_match(/illegal option/, output)
  end

  def test_invalid_option_silent
    output = capture_output do
      Rubish::Builtins.run('getopts', [':abc', 'opt', '-x'])
    end
    assert_equal '?', ENV['opt']
    assert_equal 'x', ENV['OPTARG']
    assert_equal '', output  # Silent mode
  end

  def test_missing_argument
    output = capture_output do
      Rubish::Builtins.run('getopts', ['a:', 'opt', '-a'])
    end
    assert_equal '?', ENV['opt']
    assert_match(/requires an argument/, output)
  end

  def test_missing_argument_silent
    output = capture_output do
      Rubish::Builtins.run('getopts', [':a:', 'opt', '-a'])
    end
    assert_equal ':', ENV['opt']
    assert_equal 'a', ENV['OPTARG']
    assert_equal '', output  # Silent mode
  end

  def test_end_of_options
    result = Rubish::Builtins.run('getopts', ['abc', 'opt', 'nonoption'])
    assert_false result
    assert_equal '?', ENV['opt']
  end

  def test_double_dash_ends_options
    Rubish::Builtins.run('getopts', ['abc', 'opt', '--', '-a'])
    assert_equal '?', ENV['opt']
  end

  def test_single_dash_is_not_option
    result = Rubish::Builtins.run('getopts', ['abc', 'opt', '-'])
    assert_false result
    assert_equal '?', ENV['opt']
  end

  def test_optind_advances
    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b', '-c'])
    assert_equal '2', ENV['OPTIND']

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b', '-c'])
    assert_equal '3', ENV['OPTIND']

    Rubish::Builtins.run('getopts', ['abc', 'opt', '-a', '-b', '-c'])
    assert_equal '4', ENV['OPTIND']
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
    assert_equal '3', ENV['OPTIND']

    Rubish::Builtins.reset_getopts
    assert_equal '1', ENV['OPTIND']
  end

  def test_optarg_cleared_for_no_arg_option
    Rubish::Builtins.run('getopts', ['a:b', 'opt', '-a', 'value', '-b'])
    assert_equal 'value', ENV['OPTARG']

    Rubish::Builtins.run('getopts', ['a:b', 'opt', '-a', 'value', '-b'])
    assert_nil ENV['OPTARG']
  end
end
