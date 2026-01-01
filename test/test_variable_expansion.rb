# frozen_string_literal: true

require_relative 'test_helper'

class TestVariableExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    # Save original ENV
    @original_env = ENV.to_h
  end

  def teardown
    # Restore original ENV
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def expand(line)
    @repl.send(:expand_variables, line)
  end

  def test_simple_variable
    ENV['FOO'] = 'bar'
    assert_equal 'echo bar', expand('echo $FOO')
  end

  def test_variable_at_start
    ENV['CMD'] = 'ls'
    assert_equal 'ls -la', expand('$CMD -la')
  end

  def test_variable_at_end
    ENV['EXT'] = 'txt'
    assert_equal 'file.txt', expand('file.$EXT')
  end

  def test_multiple_variables
    ENV['A'] = 'hello'
    ENV['B'] = 'world'
    assert_equal 'echo hello world', expand('echo $A $B')
  end

  def test_braced_variable
    ENV['NAME'] = 'ruby'
    assert_equal 'echo rubyish', expand('echo ${NAME}ish')
  end

  def test_undefined_variable_expands_to_empty
    ENV.delete('UNDEFINED')
    assert_equal 'echo ', expand('echo $UNDEFINED')
  end

  def test_single_quotes_prevent_expansion
    ENV['FOO'] = 'bar'
    assert_equal "echo '$FOO'", expand("echo '$FOO'")
  end

  def test_double_quotes_allow_expansion
    ENV['FOO'] = 'bar'
    assert_equal 'echo "bar"', expand('echo "$FOO"')
  end

  def test_mixed_quotes
    ENV['FOO'] = 'bar'
    assert_equal "echo 'literal' \"bar\"", expand("echo 'literal' \"$FOO\"")
  end

  def test_dollar_sign_alone
    assert_equal 'echo $', expand('echo $')
  end

  def test_dollar_followed_by_number
    # $1-$9 are now positional parameters, expand to empty if not set
    assert_equal 'echo ', expand('echo $1')
  end

  def test_variable_with_underscore
    ENV['FOO_BAR'] = 'baz'
    assert_equal 'echo baz', expand('echo $FOO_BAR')
  end

  def test_variable_with_numbers
    ENV['FOO123'] = 'baz'
    assert_equal 'echo baz', expand('echo $FOO123')
  end

  def test_braced_undefined_variable
    ENV.delete('UNDEFINED')
    assert_equal 'echo test', expand('echo ${UNDEFINED}test')
  end

  def test_home_variable
    assert_equal "echo #{ENV['HOME']}", expand('echo $HOME')
  end

  def test_path_variable
    assert_equal ENV['PATH'], expand('$PATH')
  end

  def test_no_expansion_needed
    assert_equal 'echo hello world', expand('echo hello world')
  end

  def test_escaped_in_single_quotes_complex
    ENV['X'] = 'expanded'
    assert_equal "prefix '$X' suffix", expand("prefix '$X' suffix")
  end

  # Command substitution tests
  def test_simple_command_substitution
    assert_equal 'echo hello', expand('echo $(echo hello)')
  end

  def test_command_substitution_at_start
    assert_equal 'hello world', expand('$(echo hello) world')
  end

  def test_command_substitution_at_end
    assert_equal 'say hello', expand('say $(echo hello)')
  end

  def test_multiple_command_substitutions
    assert_equal 'a b', expand('$(echo a) $(echo b)')
  end

  def test_command_substitution_in_double_quotes
    assert_equal '"hello"', expand('"$(echo hello)"')
  end

  def test_command_substitution_not_in_single_quotes
    assert_equal "'$(echo hello)'", expand("'$(echo hello)'")
  end

  def test_nested_parentheses_in_command_substitution
    assert_equal '2', expand('$(echo $((1+1)))')
  end

  def test_command_substitution_strips_trailing_newline
    result = expand('$(printf "hello\n")')
    assert_equal 'hello', result
  end

  def test_command_substitution_with_pipe
    assert_equal 'HELLO', expand('$(echo hello | tr a-z A-Z)')
  end

  def test_mixed_variable_and_command_substitution
    ENV['NAME'] = 'world'
    assert_equal 'hello world', expand('$(echo hello) $NAME')
  end

  def test_unclosed_command_substitution
    # Unclosed $( should be treated as literal $
    assert_equal 'echo $(unclosed', expand('echo $(unclosed')
  end

  # $? tests
  def test_exit_status_after_success
    @repl.send(:execute, 'true')
    assert_equal 'exit: 0', expand('exit: $?')
  end

  def test_exit_status_after_failure
    @repl.send(:execute, 'false')
    assert_equal 'exit: 1', expand('exit: $?')
  end

  def test_exit_status_initial_value
    repl = Rubish::REPL.new
    result = repl.send(:expand_variables, 'status: $?')
    assert_equal 'status: 0', result
  end

  def test_exit_status_in_double_quotes
    @repl.send(:execute, 'false')
    assert_equal '"1"', expand('"$?"')
  end

  def test_exit_status_not_in_single_quotes
    @repl.send(:execute, 'false')
    assert_equal "'$?'", expand("'$?'")
  end

  def test_exit_status_with_pipeline
    @repl.send(:execute, 'true | false')
    # Pipeline exit status is the last command
    assert_equal '1', expand('$?')
  end

  def test_exit_status_after_builtin_success
    @repl.send(:execute, 'cd .')
    assert_equal '0', expand('$?')
  end

  # $$ tests
  def test_shell_pid
    result = expand('$$')
    assert_equal Process.pid.to_s, result
  end

  def test_shell_pid_in_string
    result = expand('pid: $$')
    assert_equal "pid: #{Process.pid}", result
  end

  def test_shell_pid_in_double_quotes
    result = expand('"$$"')
    assert_equal "\"#{Process.pid}\"", result
  end

  def test_shell_pid_not_in_single_quotes
    result = expand("'$$'")
    assert_equal "'$$'", result
  end

  # $! tests
  def test_bg_pid_initial_empty
    repl = Rubish::REPL.new
    result = repl.send(:expand_variables, '$!')
    assert_equal '', result
  end

  def test_bg_pid_after_background_job
    # Run a background job
    @repl.send(:execute, 'sleep 0.1 &')
    result = expand('$!')
    # Should be a valid PID (numeric)
    assert_match(/^\d+$/, result)
    # Clean up - wait for the job
    sleep 0.2
  end

  def test_bg_pid_in_double_quotes
    @repl.send(:execute, 'sleep 0.1 &')
    result = expand('"$!"')
    assert_match(/^"\d+"$/, result)
    sleep 0.2
  end

  def test_bg_pid_not_in_single_quotes
    @repl.send(:execute, 'sleep 0.1 &')
    result = expand("'$!'")
    assert_equal "'$!'", result
    sleep 0.2
  end

  # $0 tests
  def test_script_name_default
    result = expand('$0')
    assert_equal 'rubish', result
  end

  def test_script_name_in_string
    result = expand('shell: $0')
    assert_equal 'shell: rubish', result
  end

  def test_script_name_in_double_quotes
    result = expand('"$0"')
    assert_equal '"rubish"', result
  end

  def test_script_name_not_in_single_quotes
    result = expand("'$0'")
    assert_equal "'$0'", result
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

  def test_positional_param_3
    @repl.positional_params = ['first', 'second', 'third']
    assert_equal 'third', expand('$3')
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

  def test_positional_params_in_string
    @repl.positional_params = ['hello', 'world']
    assert_equal 'say hello world', expand('say $1 $2')
  end

  def test_positional_params_in_double_quotes
    @repl.positional_params = ['value']
    assert_equal '"value"', expand('"$1"')
  end

  def test_positional_params_not_in_single_quotes
    @repl.positional_params = ['value']
    assert_equal "'$1'", expand("'$1'")
  end

  def test_all_positional_params
    @repl.positional_params = %w[a b c d e f g h i]
    assert_equal 'a b c d e f g h i', expand('$1 $2 $3 $4 $5 $6 $7 $8 $9')
  end

  # $# tests - number of positional parameters
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

  def test_param_count_in_string
    @repl.positional_params = %w[x y z]
    assert_equal 'count: 3', expand('count: $#')
  end

  def test_param_count_in_double_quotes
    @repl.positional_params = %w[a b]
    assert_equal '"2"', expand('"$#"')
  end

  def test_param_count_not_in_single_quotes
    @repl.positional_params = %w[a b]
    assert_equal "'$#'", expand("'$#'")
  end

  # $@ tests - all positional parameters
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

  def test_all_params_in_string
    @repl.positional_params = %w[hello world]
    assert_equal 'args: hello world', expand('args: $@')
  end

  def test_all_params_in_double_quotes
    @repl.positional_params = %w[a b c]
    assert_equal '"a b c"', expand('"$@"')
  end

  def test_all_params_not_in_single_quotes
    @repl.positional_params = %w[a b c]
    assert_equal "'$@'", expand("'$@'")
  end

  def test_param_count_and_all_params_together
    @repl.positional_params = %w[x y z]
    assert_equal '3 args: x y z', expand('$# args: $@')
  end
end
