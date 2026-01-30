# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_ALIASES < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_aliases_test')
    Dir.chdir(@tempdir)
    Rubish::Builtins.clear_aliases
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.clear_aliases
  end

  # Basic RUBISH_ALIASES functionality

  def test_rubish_aliases_empty_initially
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_ALIASES[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0', value
  end

  def test_rubish_aliases_single_alias
    execute('alias ll="ls -la"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_ALIASES[ll]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'ls -la', value
  end

  def test_rubish_aliases_multiple_aliases
    execute('alias ll="ls -la"')
    execute('alias la="ls -a"')
    execute('alias grep="grep --color=auto"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_ALIASES[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '3', value
  end

  def test_rubish_aliases_get_all_values
    execute('alias ll="ls -la"')
    execute('alias la="ls -a"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_ALIASES[@]} > #{output_file}")
    value = File.read(output_file).strip
    # Values are space-separated; multi-word values appear as separate words
    # "ls -la" and "ls -a" become "ls -la ls -a" which splits as ["ls", "-la", "ls", "-a"]
    assert value.include?('ls'), 'Should contain ls'
    assert value.include?('-la'), 'Should contain -la'
    assert value.include?('-a'), 'Should contain -a'
  end

  def test_rubish_aliases_get_all_keys
    execute('alias ll="ls -la"')
    execute('alias la="ls -a"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!RUBISH_ALIASES[@]} > #{output_file}")
    value = File.read(output_file).strip
    keys = value.split
    assert_include keys, 'll'
    assert_include keys, 'la'
  end

  def test_rubish_aliases_nonexistent_key
    execute('alias ll="ls -la"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_ALIASES[nonexistent]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_aliases_after_unalias
    execute('alias ll="ls -la"')
    execute('alias la="ls -a"')
    execute('unalias ll')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_ALIASES[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1', value
  end

  def test_rubish_aliases_reflects_current_aliases
    execute('alias foo="bar"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_ALIASES[foo]} > #{output_file}")
    value1 = File.read(output_file).strip
    assert_equal 'bar', value1

    execute('alias foo="baz"')
    execute("echo ${RUBISH_ALIASES[foo]} > #{output_file}")
    value2 = File.read(output_file).strip
    assert_equal 'baz', value2
  end

  # Read-only behavior

  def test_rubish_aliases_assignment_ignored
    execute('alias ll="ls -la"')
    execute('RUBISH_ALIASES=custom')
    # Should still have the alias
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_ALIASES[ll]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'ls -la', value
  end

  def test_rubish_aliases_not_in_env
    execute('alias ll="ls -la"')
    assert_nil ENV['RUBISH_ALIASES'], 'RUBISH_ALIASES should not be in ENV'
  end

  # Keys and values tests

  def test_rubish_aliases_star_expansion
    execute('alias ll="ls -la"')
    execute('alias la="ls -a"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_ALIASES[*]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '2', value
  end

  def test_rubish_aliases_with_special_chars
    execute('alias grep="grep --color=auto"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_ALIASES[grep]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'grep --color=auto', value
  end

  def test_rubish_aliases_with_quotes_in_value
    execute("alias myecho='echo test'")
    output_file = File.join(@tempdir, 'output.txt')
    # Use printf to avoid alias expansion of 'echo'
    execute("printf '%s' \"${RUBISH_ALIASES[myecho]}\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'echo test', value
  end

  # Edge cases

  def test_rubish_aliases_empty_keys
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${!RUBISH_ALIASES[@]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_aliases_empty_values
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_ALIASES[@]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  # Integration with alias command

  def test_rubish_aliases_matches_alias_output
    execute('alias ll="ls -la"')
    execute('alias la="ls -a"')
    # RUBISH_ALIASES should reflect what 'alias' shows
    assert_equal 2, Rubish::Builtins.current_state.aliases.length
    assert_equal 'ls -la', Rubish::Builtins.current_state.aliases['ll']
    assert_equal 'ls -a', Rubish::Builtins.current_state.aliases['la']
  end

  def test_rubish_aliases_updated_by_alias_command
    output_file = File.join(@tempdir, 'output.txt')

    execute("echo ${#RUBISH_ALIASES[@]} > #{output_file}")
    count1 = File.read(output_file).strip.to_i

    execute('alias newcmd="echo hello"')
    execute("echo ${#RUBISH_ALIASES[@]} > #{output_file}")
    count2 = File.read(output_file).strip.to_i

    assert_equal count1 + 1, count2
  end

  # Conditional tests

  def test_rubish_aliases_in_conditional
    execute('alias ll="ls -la"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ -n ${RUBISH_ALIASES[ll]} ]]; then echo yes; else echo no; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'yes', value
  end

  def test_rubish_aliases_nonexistent_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ -n ${RUBISH_ALIASES[nonexistent]} ]]; then echo yes; else echo no; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'no', value
  end

  # Iteration over aliases

  def test_rubish_aliases_iterate_keys
    execute('alias a="cmd1"')
    execute('alias b="cmd2"')
    execute('alias c="cmd3"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!RUBISH_ALIASES[@]} > #{output_file}")
    value = File.read(output_file).strip
    keys = value.split
    assert_equal 3, keys.length
    assert_include keys, 'a'
    assert_include keys, 'b'
    assert_include keys, 'c'
  end
end
