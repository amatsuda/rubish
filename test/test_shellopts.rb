# frozen_string_literal: true

require_relative 'test_helper'

class TestShellopts < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    # Save original set_options state
    @original_set_options = Rubish::Builtins.set_options.dup
    @original_shell_options = Rubish::Builtins.shell_options.dup
  end

  def teardown
    # Restore original state
    Rubish::Builtins.set_options.clear
    @original_set_options.each { |k, v| Rubish::Builtins.set_options[k] = v }
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  # Test SHELLOPTS returns colon-separated enabled set options
  def test_shellopts_default
    result = Rubish::Builtins.shellopts
    # Default enabled options are B (braceexpand) and H (histexpand)
    assert_includes result.split(':'), 'braceexpand'
    assert_includes result.split(':'), 'histexpand'
  end

  # Test SHELLOPTS updates when set -o enables options
  def test_shellopts_after_enabling_option
    execute('set -o errexit')
    result = Rubish::Builtins.shellopts
    assert_includes result.split(':'), 'errexit'
  end

  # Test SHELLOPTS updates when set +o disables options
  def test_shellopts_after_disabling_option
    execute('set +o braceexpand')
    result = Rubish::Builtins.shellopts
    refute_includes result.split(':'), 'braceexpand'
  end

  # Test SHELLOPTS is sorted alphabetically
  def test_shellopts_sorted
    execute('set -o errexit')
    execute('set -o xtrace')
    result = Rubish::Builtins.shellopts
    parts = result.split(':')
    assert_equal parts.sort, parts
  end

  # Test SHELLOPTS variable expansion
  def test_shellopts_variable_expansion
    result = @repl.send(:expand_single_arg, '$SHELLOPTS')
    assert_includes result, 'braceexpand'
  end

  # Test RUBISHOPTS returns colon-separated enabled shopt options
  def test_rubishopts_default
    result = Rubish::Builtins.rubishopts
    # Default enabled options
    assert_includes result.split(':'), 'cmdhist'
    assert_includes result.split(':'), 'expand_aliases'
    assert_includes result.split(':'), 'interactive_comments'
  end

  # Test RUBISHOPTS updates when shopt -s enables options
  def test_rubishopts_after_enabling_option
    execute('shopt -s dotglob')
    result = Rubish::Builtins.rubishopts
    assert_includes result.split(':'), 'dotglob'
  end

  # Test RUBISHOPTS updates when shopt -u disables options
  def test_rubishopts_after_disabling_option
    execute('shopt -u cmdhist')
    result = Rubish::Builtins.rubishopts
    refute_includes result.split(':'), 'cmdhist'
  end

  # Test RUBISHOPTS is sorted alphabetically
  def test_rubishopts_sorted
    execute('shopt -s dotglob')
    execute('shopt -s globstar')
    result = Rubish::Builtins.rubishopts
    parts = result.split(':')
    assert_equal parts.sort, parts
  end

  # Test RUBISHOPTS variable expansion
  def test_rubishopts_variable_expansion
    result = @repl.send(:expand_single_arg, '$RUBISHOPTS')
    assert_includes result, 'cmdhist'
  end

  # Test via echo command
  def test_shellopts_via_echo
    output = capture_output { execute('echo $SHELLOPTS') }
    assert_includes output, 'braceexpand'
  end

  def test_rubishopts_via_echo
    output = capture_output { execute('echo $RUBISHOPTS') }
    assert_includes output, 'cmdhist'
  end
end
