# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_COMPAT < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_compat_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.shell_options.clear
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic RUBISH_COMPAT functionality

  def test_rubish_compat_can_be_set
    execute('RUBISH_COMPAT=1.0')
    assert_equal '1.0', ENV['RUBISH_COMPAT']
  end

  def test_rubish_compat_can_be_exported
    execute('export RUBISH_COMPAT=1.0')
    assert_equal '1.0', ENV['RUBISH_COMPAT']
  end

  def test_rubish_compat_can_be_read
    ENV['RUBISH_COMPAT'] = '1.0'
    execute("echo $RUBISH_COMPAT > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1.0', result
  end

  def test_rubish_compat_unset_is_empty
    ENV.delete('RUBISH_COMPAT')
    execute("echo \"x${RUBISH_COMPAT}x\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'xx', result
  end

  # compat_level method tests

  def test_compat_level_from_env_var
    ENV['RUBISH_COMPAT'] = '1.0'
    assert_equal 10, Rubish::Builtins.compat_level
  end

  def test_compat_level_from_env_var_11
    ENV['RUBISH_COMPAT'] = '1.1'
    assert_equal 11, Rubish::Builtins.compat_level
  end

  def test_compat_level_from_env_var_single_digit
    ENV['RUBISH_COMPAT'] = '2'
    assert_equal 20, Rubish::Builtins.compat_level
  end

  def test_compat_level_nil_when_not_set
    ENV.delete('RUBISH_COMPAT')
    Rubish::Builtins.shell_options.clear
    assert_nil Rubish::Builtins.compat_level
  end

  def test_compat_level_from_shopt
    ENV.delete('RUBISH_COMPAT')
    Rubish::Builtins.shell_options['compat10'] = true
    assert_equal 10, Rubish::Builtins.compat_level
  end

  def test_env_var_takes_precedence_over_shopt
    ENV['RUBISH_COMPAT'] = '1.1'
    Rubish::Builtins.shell_options['compat10'] = true
    # ENV var should take precedence
    assert_equal 11, Rubish::Builtins.compat_level
  end

  # compat_level? method tests

  def test_compat_level_check_true
    ENV['RUBISH_COMPAT'] = '1.0'
    assert Rubish::Builtins.compat_level?(10)
    assert Rubish::Builtins.compat_level?(11)
    assert Rubish::Builtins.compat_level?(20)
  end

  def test_compat_level_check_false
    ENV['RUBISH_COMPAT'] = '1.1'
    assert_false Rubish::Builtins.compat_level?(10)
    assert Rubish::Builtins.compat_level?(11)
  end

  def test_compat_level_check_nil_when_not_set
    ENV.delete('RUBISH_COMPAT')
    Rubish::Builtins.shell_options.clear
    assert_nil Rubish::Builtins.compat_level?(10)
  end

  # shopt compat10 option tests

  def test_shopt_compat10_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat10')
  end

  def test_shopt_compat10_default_false
    Rubish::Builtins.shell_options.clear
    assert_false Rubish::Builtins.shopt_enabled?('compat10')
  end

  def test_shopt_set_compat10
    execute('shopt -s compat10')
    assert Rubish::Builtins.shopt_enabled?('compat10')
  end

  def test_shopt_unset_compat10
    Rubish::Builtins.shell_options['compat10'] = true
    execute('shopt -u compat10')
    assert_false Rubish::Builtins.shopt_enabled?('compat10')
  end

  # set_compat_level method tests

  def test_set_compat_level_10
    Rubish::Builtins.set_compat_level('1.0')
    assert Rubish::Builtins.shell_options['compat10']
  end

  def test_set_compat_level_clears_others
    Rubish::Builtins.shell_options['compat10'] = true
    Rubish::Builtins.set_compat_level('1.1')
    # compat10 should be cleared (compat11 doesn't exist yet, but compat10 should be false)
    assert_false Rubish::Builtins.shell_options['compat10']
  end

  # Unset RUBISH_COMPAT

  def test_unset_rubish_compat
    ENV['RUBISH_COMPAT'] = '1.0'
    execute('unset RUBISH_COMPAT')
    assert_nil ENV['RUBISH_COMPAT']
  end

  # RUBISH_COMPAT in subshell

  def test_rubish_compat_in_subshell
    ENV['RUBISH_COMPAT'] = '1.0'
    execute("(echo $RUBISH_COMPAT) > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1.0', result
  end

  # RUBISH_COMPAT inherited by child processes

  def test_rubish_compat_inherited
    ENV['RUBISH_COMPAT'] = '1.0'
    execute("ruby -e 'puts ENV[\"RUBISH_COMPAT\"]' > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1.0', result
  end

  # Various version formats

  def test_rubish_compat_version_formats
    ENV['RUBISH_COMPAT'] = '1.0'
    assert_equal 10, Rubish::Builtins.compat_level

    ENV['RUBISH_COMPAT'] = '2.5'
    assert_equal 25, Rubish::Builtins.compat_level

    ENV['RUBISH_COMPAT'] = '10.0'
    assert_equal 100, Rubish::Builtins.compat_level
  end

  # Conditional behavior based on RUBISH_COMPAT

  def test_rubish_compat_conditional
    ENV['RUBISH_COMPAT'] = '1.0'
    execute("if [ -n \"$RUBISH_COMPAT\" ]; then echo compat; else echo current; fi > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'compat', result
  end

  def test_rubish_compat_not_set_conditional
    ENV.delete('RUBISH_COMPAT')
    execute("if [ -n \"$RUBISH_COMPAT\" ]; then echo compat; else echo current; fi > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'current', result
  end

  # COMPAT_OPTIONS constant

  def test_compat_options_includes_compat10
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat10'
  end
end
