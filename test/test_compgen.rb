# frozen_string_literal: true

require_relative 'test_helper'

class TestCompgen < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_compgen_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)

    # Create a REPL to initialize the context
    @repl = Rubish::REPL.new
    Rubish::Builtins.set_array('COMPREPLY', [])
    Rubish::Builtins.clear_completions
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.clear_completion_context
    Rubish::Builtins.set_array('COMPREPLY', [])
  end

  # ==========================================================================
  # -W wordlist tests
  # ==========================================================================

  def test_wordlist_basic
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'apple banana cherry', ''])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'apple'
    assert_includes lines, 'banana'
    assert_includes lines, 'cherry'
  end

  def test_wordlist_with_prefix
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'apple banana cherry', 'a'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'apple'
    assert_not_includes lines, 'banana'
    assert_not_includes lines, 'cherry'
  end

  def test_wordlist_no_match
    output = capture_output do
      result = Rubish::Builtins.compgen(['-W', 'apple banana cherry', 'z'])
      assert_false result
    end
    assert_empty output.strip
  end

  def test_wordlist_multiple_matches
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'bar baz bat foo', 'ba'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'bar'
    assert_includes lines, 'baz'
    assert_includes lines, 'bat'
    assert_not_includes lines, 'foo'
  end

  # ==========================================================================
  # -F function tests
  # ==========================================================================

  def test_function_with_builtin_completion
    Rubish::Builtins.set_completion_context(
      line: 'git ',
      point: 4,
      words: ['git', ''],
      cword: 1
    )

    results = Rubish::Builtins.generate_completions({actions: [], function: '_git'}, 'co')
    assert_includes results, 'commit'
    assert_includes results, 'config'
    assert_includes results, 'column'
  end

  def test_function_preserves_compreply
    Rubish::Builtins.set_completion_context(
      line: 'git ',
      point: 4,
      words: ['git', ''],
      cword: 1
    )

    # Set up initial COMPREPLY AFTER set_completion_context (which clears it)
    Rubish::Builtins.compreply = ['original']

    Rubish::Builtins.generate_completions({actions: [], function: '_git'}, '')

    # COMPREPLY should be restored
    assert_equal ['original'], Rubish::Builtins.compreply
  end

  # ==========================================================================
  # -C command tests
  # ==========================================================================

  def test_command_basic
    results = Rubish::Builtins.generate_completions({actions: [], command: 'printf "foo\nbar\nbaz\n"'}, '')
    assert_includes results, 'foo'
    assert_includes results, 'bar'
    assert_includes results, 'baz'
  end

  def test_command_with_filter
    results = Rubish::Builtins.generate_completions({actions: [], command: 'printf "foo\nbar\nbaz\n"'}, 'b')
    assert_includes results, 'bar'
    assert_includes results, 'baz'
    assert_not_includes results, 'foo'
  end

  def test_command_empty_output
    results = Rubish::Builtins.generate_completions({actions: [], command: 'true'}, '')
    assert_empty results
  end

  # ==========================================================================
  # -A action tests
  # ==========================================================================

  def test_action_keyword
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'keyword', 'i'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'if'
    assert_includes lines, 'in'
  end

  def test_action_signal
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'signal', 'INT'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'INT'
  end

  def test_action_signal_all
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'signal', ''])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'HUP'
    assert_includes lines, 'KILL'
    assert_includes lines, 'TERM'
  end

  def test_action_shopt
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'shopt', 'ext'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'extdebug'
    assert_includes lines, 'extglob'
  end

  def test_action_setopt
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'setopt', 'no'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'noclobber'
    assert_includes lines, 'noexec'
    assert_includes lines, 'noglob'
  end

  def test_action_builtin
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'builtin', 'ec'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'echo'
  end

  def test_action_hostname
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'hostname', 'local'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'localhost'
  end

  def test_action_enabled
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'enabled', 'ec'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'echo'
  end

  def test_action_disabled
    # Disable a builtin first
    Rubish::Builtins.disabled_builtins.add('testbuiltin')

    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'disabled', 'test'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'testbuiltin'
  ensure
    Rubish::Builtins.disabled_builtins.delete('testbuiltin')
  end

  def test_action_arrayvar
    Rubish::Builtins.set_array('myarray', ['a', 'b', 'c'])
    Rubish::Builtins.set_array('mylist', ['x', 'y', 'z'])

    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'arrayvar', 'my'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'myarray'
    assert_includes lines, 'mylist'
  ensure
    Rubish::Builtins.unset_array('myarray')
    Rubish::Builtins.unset_array('mylist')
  end

  def test_action_binding
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'binding', 'complete'])
    end
    lines = output.strip.split("\n")
    assert lines.any? { |l| l.include?('complete') }
  end

  def test_action_helptopic
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'helptopic', 'ec'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'echo'
  end

  # ==========================================================================
  # -X filter tests
  # ==========================================================================

  def test_filter_glob
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'foo.txt bar.rb baz.txt', '-X', '*.txt'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'bar.rb'
    assert_not_includes lines, 'foo.txt'
    assert_not_includes lines, 'baz.txt'
  end

  def test_filter_question_mark
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'foo bar baz', '-X', 'ba?'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'foo'
    assert_not_includes lines, 'bar'
    assert_not_includes lines, 'baz'
  end

  def test_filter_no_match
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'foo bar baz', '-X', 'xyz'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'foo'
    assert_includes lines, 'bar'
    assert_includes lines, 'baz'
  end

  # ==========================================================================
  # -P prefix and -S suffix tests
  # ==========================================================================

  def test_prefix_only
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'one two', '-P', 'pre_'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'pre_one'
    assert_includes lines, 'pre_two'
  end

  def test_suffix_only
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'one two', '-S', '_suf'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'one_suf'
    assert_includes lines, 'two_suf'
  end

  def test_prefix_and_suffix
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'one two', '-P', 'pre_', '-S', '_suf'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'pre_one_suf'
    assert_includes lines, 'pre_two_suf'
  end

  # ==========================================================================
  # -G glob pattern tests
  # ==========================================================================

  def test_glob_pattern
    # Create some test files
    FileUtils.touch('test1.txt')
    FileUtils.touch('test2.txt')
    FileUtils.touch('other.rb')

    output = capture_output do
      Rubish::Builtins.compgen(['-G', '*.txt'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'test1.txt'
    assert_includes lines, 'test2.txt'
    assert_not_includes lines, 'other.rb'
  end

  # ==========================================================================
  # Short flag tests
  # ==========================================================================

  def test_short_flag_a_alias
    Rubish::Builtins.current_state.aliases['myalias'] = 'ls -la'

    output = capture_output do
      Rubish::Builtins.compgen(['-a', 'my'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'myalias'
  ensure
    Rubish::Builtins.current_state.aliases.delete('myalias')
  end

  def test_short_flag_b_builtin
    output = capture_output do
      Rubish::Builtins.compgen(['-b', 'ec'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'echo'
  end

  def test_short_flag_d_directory
    FileUtils.mkdir('testdir')

    output = capture_output do
      Rubish::Builtins.compgen(['-d', 'test'])
    end
    lines = output.strip.split("\n")
    assert lines.any? { |l| l.include?('testdir') }
  end

  def test_short_flag_f_file
    FileUtils.touch('testfile.txt')
    FileUtils.mkdir('testdir')

    output = capture_output do
      Rubish::Builtins.compgen(['-f', 'test'])
    end
    lines = output.strip.split("\n")
    assert lines.any? { |l| l.include?('testfile') }
    assert lines.any? { |l| l.include?('testdir') }
  end

  def test_short_flag_v_variable
    ENV['MY_TEST_VAR'] = 'value'

    output = capture_output do
      Rubish::Builtins.compgen(['-v', 'MY_TEST'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'MY_TEST_VAR'
  end

  # ==========================================================================
  # Combined options tests
  # ==========================================================================

  def test_combined_wordlist_and_filter
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'foo.txt bar.rb baz.txt', '-X', '*.txt', 'b'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'bar.rb'
    assert_equal 1, lines.length
  end

  def test_combined_wordlist_prefix_suffix
    output = capture_output do
      Rubish::Builtins.compgen(['-W', 'one two', '-P', '(', '-S', ')', 'o'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, '(one)'
  end

  def test_combined_multiple_actions
    output = capture_output do
      Rubish::Builtins.compgen(['-A', 'keyword', '-A', 'signal', 'i'])
    end
    lines = output.strip.split("\n")
    assert_includes lines, 'if'
    assert_includes lines, 'in'
    assert_includes lines, 'INT'
    assert_includes lines, 'ILL'
  end

  # ==========================================================================
  # Return value tests
  # ==========================================================================

  def test_returns_true_on_match
    result = nil
    capture_output do
      result = Rubish::Builtins.compgen(['-W', 'foo bar', 'f'])
    end
    assert result
  end

  def test_returns_false_on_no_match
    result = nil
    capture_output do
      result = Rubish::Builtins.compgen(['-W', 'foo bar', 'z'])
    end
    assert_false result
  end

  # ==========================================================================
  # glob_to_regex tests
  # ==========================================================================

  def test_glob_to_regex_star
    regex = Rubish::Builtins.glob_to_regex('*.txt')
    assert_match regex, 'foo.txt'
    assert_match regex, 'bar.txt'
    assert_no_match regex, 'foo.rb'
  end

  def test_glob_to_regex_question
    regex = Rubish::Builtins.glob_to_regex('fo?')
    assert_match regex, 'foo'
    assert_match regex, 'fob'
    assert_no_match regex, 'fooo'
  end

  def test_glob_to_regex_negation
    regex = Rubish::Builtins.glob_to_regex('!*.txt')
    assert_match regex, 'foo.txt'  # Negation is stripped for -X filter
  end

  def test_glob_to_regex_special_chars
    regex = Rubish::Builtins.glob_to_regex('foo.bar')
    assert_match regex, 'foo.bar'
    assert_no_match regex, 'fooxbar'
  end
end
