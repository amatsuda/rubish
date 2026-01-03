# frozen_string_literal: true

require_relative 'test_helper'

class TestHelp < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test help is a builtin
  def test_help_is_builtin
    assert Rubish::Builtins.builtin?('help')
  end

  # Test help without arguments lists all builtins
  def test_help_no_args_lists_builtins
    output = capture_output { Rubish::Builtins.run('help', []) }
    assert_match(/Shell builtin commands:/, output)
    assert_match(/cd/, output)
    assert_match(/echo/, output)
    assert_match(/exit/, output)
  end

  # Test help with specific builtin
  def test_help_specific_builtin
    output = capture_output { Rubish::Builtins.run('help', ['cd']) }
    assert_match(/cd:/, output)
    assert_match(/Change the current directory/, output)
  end

  # Test help with -d flag shows short descriptions
  def test_help_d_short_desc
    output = capture_output { Rubish::Builtins.run('help', ['-d']) }
    assert_match(/cd - Change the current directory/, output)
    assert_match(/echo - Write arguments to standard output/, output)
  end

  # Test help with -s flag shows synopsis only
  def test_help_s_synopsis_only
    output = capture_output { Rubish::Builtins.run('help', ['-s', 'cd']) }
    assert_match(/cd: cd \[-L\|-P\] \[dir\]/, output)
    assert_no_match(/Change the current directory/, output)
  end

  # Test help with -m flag shows manpage format
  def test_help_m_manpage
    output = capture_output { Rubish::Builtins.run('help', ['-m', 'cd']) }
    assert_match(/NAME/, output)
    assert_match(/SYNOPSIS/, output)
    assert_match(/DESCRIPTION/, output)
    assert_match(/cd - change the current directory/, output)
  end

  # Test help with -m flag and options section
  def test_help_m_manpage_with_options
    output = capture_output { Rubish::Builtins.run('help', ['-m', 'echo']) }
    assert_match(/OPTIONS/, output)
    assert_match(/-n/, output)
    assert_match(/-e/, output)
  end

  # Test help with pattern matching
  def test_help_pattern_matching
    output = capture_output { Rubish::Builtins.run('help', ['ec*']) }
    assert_match(/echo:/, output)
  end

  # Test help with multiple patterns
  def test_help_multiple_patterns
    output = capture_output { Rubish::Builtins.run('help', ['cd', 'pwd']) }
    assert_match(/cd:/, output)
    assert_match(/pwd:/, output)
  end

  # Test help with nonexistent command
  def test_help_nonexistent
    output = capture_output do
      result = Rubish::Builtins.run('help', ['nonexistent'])
      assert_false result
    end
    assert_match(/no help topics match 'nonexistent'/, output)
  end

  # Test help with invalid option
  def test_help_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('help', ['-z'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test help shows options for test command
  def test_help_test_options
    output = capture_output { Rubish::Builtins.run('help', ['test']) }
    assert_match(/-e file/, output)
    assert_match(/-f file/, output)
    assert_match(/-d file/, output)
  end

  # Test help for special builtins
  def test_help_special_builtins
    # Test help for : (colon)
    output = capture_output { Rubish::Builtins.run('help', [':']) }
    assert_match(/Null command/, output)

    # Test help for . (dot)
    output = capture_output { Rubish::Builtins.run('help', ['.']) }
    assert_match(/Read and execute commands/, output)

    # Test help for [
    output = capture_output { Rubish::Builtins.run('help', ['[']) }
    assert_match(/Evaluate conditional expression/, output)
  end

  # Test type identifies help as builtin
  def test_type_identifies_help_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['help']) }
    assert_match(/help is a shell builtin/, output)
  end

  # Test help via REPL
  def test_help_via_repl
    output = capture_output { execute('help cd') }
    assert_match(/cd:/, output)
    assert_match(/Change the current directory/, output)
  end

  # Test help -d for specific command
  def test_help_d_specific_command
    output = capture_output { Rubish::Builtins.run('help', ['-d', 'echo']) }
    assert_equal "echo - Write arguments to standard output.\n", output
  end

  # Test help shows help for help
  def test_help_help
    output = capture_output { Rubish::Builtins.run('help', ['help']) }
    assert_match(/help: help \[-dms\] \[pattern \.\.\.\]/, output)
    assert_match(/Display information about builtin commands/, output)
    assert_match(/-d/, output)
    assert_match(/-m/, output)
    assert_match(/-s/, output)
  end

  # Test all builtins have documentation
  def test_all_builtins_have_help
    Rubish::Builtins::COMMANDS.each do |cmd|
      assert Rubish::Builtins::BUILTIN_HELP.key?(cmd), "Missing help for '#{cmd}'"
    end
  end

  # Test help documentation has required fields
  def test_help_documentation_structure
    Rubish::Builtins::BUILTIN_HELP.each do |cmd, info|
      assert info.key?(:synopsis), "Missing synopsis for '#{cmd}'"
      assert info.key?(:description), "Missing description for '#{cmd}'"
      assert info[:synopsis].is_a?(String), "Synopsis for '#{cmd}' is not a string"
      assert info[:description].is_a?(String), "Description for '#{cmd}' is not a string"
    end
  end
end
