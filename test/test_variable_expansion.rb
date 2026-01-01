# frozen_string_literal: true

require_relative 'test_helper'

class TestVariableExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h
    @tempdir = Dir.mktmpdir('rubish_var_test')
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  def expand(arg)
    @repl.send(:expand_single_arg, arg)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic variable expansion
  def test_simple_variable
    ENV['FOO'] = 'bar'
    assert_equal 'bar', expand('$FOO')
  end

  def test_variable_with_suffix
    ENV['EXT'] = 'txt'
    assert_equal 'file.txt', expand('file.$EXT')
  end

  def test_braced_variable
    ENV['NAME'] = 'ruby'
    assert_equal 'rubyish', expand('${NAME}ish')
  end

  def test_undefined_variable_expands_to_empty
    ENV.delete('UNDEFINED')
    assert_equal '', expand('$UNDEFINED')
  end

  def test_single_quotes_prevent_expansion
    ENV['FOO'] = 'bar'
    assert_equal '$FOO', expand("'$FOO'")
  end

  def test_double_quotes_allow_expansion
    ENV['FOO'] = 'bar'
    assert_equal 'bar', expand('"$FOO"')
  end

  def test_variable_with_underscore
    ENV['FOO_BAR'] = 'baz'
    assert_equal 'baz', expand('$FOO_BAR')
  end

  def test_variable_with_numbers
    ENV['FOO123'] = 'baz'
    assert_equal 'baz', expand('$FOO123')
  end

  def test_braced_undefined_variable
    ENV.delete('UNDEFINED')
    assert_equal 'test', expand('${UNDEFINED}test')
  end

  def test_home_variable
    assert_equal ENV['HOME'], expand('$HOME')
  end

  def test_no_expansion_needed
    assert_equal 'hello', expand('hello')
  end

  # Command substitution tests
  def test_simple_command_substitution
    assert_equal 'hello', expand('$(echo hello)')
  end

  def test_command_substitution_in_double_quotes
    assert_equal 'hello', expand('"$(echo hello)"')
  end

  def test_command_substitution_not_in_single_quotes
    assert_equal '$(echo hello)', expand("'$(echo hello)'")
  end

  def test_command_substitution_strips_trailing_newline
    result = expand('$(printf "hello\n")')
    assert_equal 'hello', result
  end

  def test_command_substitution_with_pipe
    assert_equal 'HELLO', expand('$(echo hello | tr a-z A-Z)')
  end

  # Execution tests for multi-word expansion
  def test_multiple_variables_in_execution
    ENV['A'] = 'hello'
    ENV['B'] = 'world'
    execute("echo $A $B > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  def test_mixed_variable_and_command_substitution
    ENV['NAME'] = 'world'
    execute("echo $(echo hello) $NAME > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  # $? tests
  def test_exit_status_after_success
    execute('true')
    assert_equal '0', expand('$?')
  end

  def test_exit_status_after_failure
    execute('false')
    assert_equal '1', expand('$?')
  end

  def test_exit_status_initial_value
    repl = Rubish::REPL.new
    result = repl.send(:expand_single_arg, '$?')
    assert_equal '0', result
  end

  def test_exit_status_in_double_quotes
    execute('false')
    assert_equal '1', expand('"$?"')
  end

  def test_exit_status_not_in_single_quotes
    execute('false')
    assert_equal '$?', expand("'$?'")
  end

  def test_exit_status_with_pipeline
    execute('true | false')
    assert_equal '1', expand('$?')
  end

  def test_exit_status_after_builtin_success
    execute('cd .')
    assert_equal '0', expand('$?')
  end

  # $$ tests
  def test_shell_pid
    result = expand('$$')
    assert_equal Process.pid.to_s, result
  end

  def test_shell_pid_in_double_quotes
    result = expand('"$$"')
    assert_equal Process.pid.to_s, result
  end

  def test_shell_pid_not_in_single_quotes
    result = expand("'$$'")
    assert_equal '$$', result
  end

  # $! tests
  def test_bg_pid_initial_empty
    repl = Rubish::REPL.new
    result = repl.send(:expand_single_arg, '$!')
    assert_equal '', result
  end

  def test_bg_pid_after_background_job
    execute('sleep 0.1 &')
    result = expand('$!')
    assert_match(/^\d+$/, result)
    sleep 0.2
  end

  def test_bg_pid_not_in_single_quotes
    execute('sleep 0.1 &')
    result = expand("'$!'")
    assert_equal '$!', result
    sleep 0.2
  end

  # $0 tests
  def test_script_name_default
    result = expand('$0')
    assert_equal 'rubish', result
  end

  def test_script_name_in_double_quotes
    result = expand('"$0"')
    assert_equal 'rubish', result
  end

  def test_script_name_not_in_single_quotes
    result = expand("'$0'")
    assert_equal '$0', result
  end

  def test_script_name_can_be_set
    @repl.script_name = '/path/to/script.sh'
    result = expand('$0')
    assert_equal '/path/to/script.sh', result
  end

  # $1-$9 positional parameters tests
  def test_positional_param_1
    @repl.positional_params = ['first', 'second', 'third']
    assert_equal 'first', expand('$1')
  end

  def test_positional_param_2
    @repl.positional_params = ['first', 'second', 'third']
    assert_equal 'second', expand('$2')
  end

  def test_positional_param_9
    @repl.positional_params = %w[a b c d e f g h i]
    assert_equal 'i', expand('$9')
  end

  def test_positional_param_unset
    @repl.positional_params = ['only_one']
    assert_equal '', expand('$2')
  end

  def test_positional_params_empty
    @repl.positional_params = []
    assert_equal '', expand('$1')
  end

  def test_positional_params_in_double_quotes
    @repl.positional_params = ['value']
    assert_equal 'value', expand('"$1"')
  end

  def test_positional_params_not_in_single_quotes
    @repl.positional_params = ['value']
    assert_equal '$1', expand("'$1'")
  end

  # $# tests
  def test_param_count_zero
    @repl.positional_params = []
    assert_equal '0', expand('$#')
  end

  def test_param_count_one
    @repl.positional_params = ['single']
    assert_equal '1', expand('$#')
  end

  def test_param_count_multiple
    @repl.positional_params = %w[a b c d e]
    assert_equal '5', expand('$#')
  end

  def test_param_count_in_double_quotes
    @repl.positional_params = %w[a b]
    assert_equal '2', expand('"$#"')
  end

  def test_param_count_not_in_single_quotes
    @repl.positional_params = %w[a b]
    assert_equal '$#', expand("'$#'")
  end

  # $@ tests
  def test_all_params_empty
    @repl.positional_params = []
    assert_equal '', expand('$@')
  end

  def test_all_params_one
    @repl.positional_params = ['single']
    assert_equal 'single', expand('$@')
  end

  def test_all_params_multiple
    @repl.positional_params = %w[foo bar baz]
    assert_equal 'foo bar baz', expand('$@')
  end

  def test_all_params_in_double_quotes
    @repl.positional_params = %w[a b c]
    assert_equal 'a b c', expand('"$@"')
  end

  def test_all_params_not_in_single_quotes
    @repl.positional_params = %w[a b c]
    assert_equal '$@', expand("'$@'")
  end
end
