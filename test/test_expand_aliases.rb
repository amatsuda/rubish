# frozen_string_literal: true

require_relative 'test_helper'

class TestExpandAliases < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_aliases = Rubish::Builtins.aliases.dup
    @tempdir = Dir.mktmpdir('rubish_expand_aliases_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.clear_aliases
    @original_aliases.each { |k, v| Rubish::Builtins.aliases[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # expand_aliases is enabled by default
  def test_expand_aliases_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('expand_aliases')
  end

  def test_expand_aliases_can_be_disabled
    execute('shopt -u expand_aliases')
    assert_false Rubish::Builtins.shopt_enabled?('expand_aliases')
  end

  def test_expand_aliases_can_be_enabled
    execute('shopt -u expand_aliases')
    execute('shopt -s expand_aliases')
    assert Rubish::Builtins.shopt_enabled?('expand_aliases')
  end

  # Test alias expansion with expand_aliases enabled (default)
  def test_alias_expanded_by_default
    execute('alias greet="echo hello"')
    execute("greet > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_alias_with_arguments_expanded
    execute('alias myecho="echo"')
    execute("myecho world > #{output_file}")
    assert_equal "world\n", File.read(output_file)
  end

  def test_multiple_aliases_expanded
    execute('alias first="echo one"')
    execute('alias second="echo two"')
    execute("first > #{output_file}")
    assert_equal "one\n", File.read(output_file)
    execute("second > #{output_file}")
    assert_equal "two\n", File.read(output_file)
  end

  # Test alias NOT expanded when expand_aliases is disabled
  def test_alias_not_expanded_when_disabled
    execute('alias ll="ls -la"')
    execute('shopt -u expand_aliases')

    # When expand_aliases is disabled, 'll' is treated as a command, not an alias
    # This should fail (command not found) or produce different output
    # We test by checking that the alias is NOT expanded
    result = Rubish::Builtins.expand_alias('ll')
    assert_equal 'll', result
  end

  def test_alias_expansion_method_respects_option
    execute('alias myalias="expanded_value"')

    # With expand_aliases enabled
    result1 = Rubish::Builtins.expand_alias('myalias arg1 arg2')
    assert_equal 'expanded_value arg1 arg2', result1

    # With expand_aliases disabled
    execute('shopt -u expand_aliases')
    result2 = Rubish::Builtins.expand_alias('myalias arg1 arg2')
    assert_equal 'myalias arg1 arg2', result2
  end

  # Test toggle behavior
  def test_toggle_expand_aliases
    execute('alias testalias="echo expanded"')

    # Default: enabled
    result1 = Rubish::Builtins.expand_alias('testalias')
    assert_equal 'echo expanded', result1

    # Disable
    execute('shopt -u expand_aliases')
    result2 = Rubish::Builtins.expand_alias('testalias')
    assert_equal 'testalias', result2

    # Re-enable
    execute('shopt -s expand_aliases')
    result3 = Rubish::Builtins.expand_alias('testalias')
    assert_equal 'echo expanded', result3
  end

  # Test that non-aliases are not affected
  def test_non_alias_not_affected
    result = Rubish::Builtins.expand_alias('echo hello')
    assert_equal 'echo hello', result
  end

  def test_non_alias_not_affected_when_disabled
    execute('shopt -u expand_aliases')
    result = Rubish::Builtins.expand_alias('echo hello')
    assert_equal 'echo hello', result
  end

  # Test empty line
  def test_empty_line
    result = Rubish::Builtins.expand_alias('')
    assert_equal '', result
  end

  def test_empty_line_when_disabled
    execute('shopt -u expand_aliases')
    result = Rubish::Builtins.expand_alias('')
    assert_equal '', result
  end

  # Test alias with trailing space (for chained aliases in bash)
  def test_alias_with_trailing_space
    execute('alias sudo="sudo "')
    result = Rubish::Builtins.expand_alias('sudo ls')
    assert_equal 'sudo  ls', result
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt expand_aliases')
    end
    assert_match(/expand_aliases/, output)
    assert_match(/on/, output)

    execute('shopt -u expand_aliases')

    output = capture_output do
      execute('shopt expand_aliases')
    end
    assert_match(/expand_aliases/, output)
    assert_match(/off/, output)
  end

  # Test that alias definition still works when expand_aliases is disabled
  def test_alias_definition_works_when_disabled
    execute('shopt -u expand_aliases')
    execute('alias newalias="echo new"')

    # Alias should be defined
    assert Rubish::Builtins.aliases.key?('newalias')
    assert_equal 'echo new', Rubish::Builtins.aliases['newalias']

    # But not expanded
    result = Rubish::Builtins.expand_alias('newalias')
    assert_equal 'newalias', result

    # Re-enable and verify expansion works
    execute('shopt -s expand_aliases')
    result = Rubish::Builtins.expand_alias('newalias')
    assert_equal 'echo new', result
  end

  # Test unalias still works when expand_aliases is disabled
  def test_unalias_works_when_disabled
    execute('alias removeme="echo remove"')
    execute('shopt -u expand_aliases')
    execute('unalias removeme')

    assert_false Rubish::Builtins.aliases.key?('removeme')
  end
end
