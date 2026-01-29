# frozen_string_literal: true

require_relative 'test_helper'

class TestMultilineString < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_multiline_test')
    @saved_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  def script_file
    File.join(@tempdir, 'script.sh')
  end

  # Test has_unclosed_quotes helper
  def test_has_unclosed_quotes_single_open
    assert Rubish::Builtins.has_unclosed_quotes("x='hello")
  end

  def test_has_unclosed_quotes_single_closed
    refute Rubish::Builtins.has_unclosed_quotes("x='hello'")
  end

  def test_has_unclosed_quotes_double_open
    assert Rubish::Builtins.has_unclosed_quotes('x="hello')
  end

  def test_has_unclosed_quotes_double_closed
    refute Rubish::Builtins.has_unclosed_quotes('x="hello"')
  end

  def test_has_unclosed_quotes_with_newline
    assert Rubish::Builtins.has_unclosed_quotes("x='line1\n")
  end

  def test_has_unclosed_quotes_multiline_closed
    refute Rubish::Builtins.has_unclosed_quotes("x='line1\nline2'")
  end

  def test_has_unclosed_quotes_nested_quotes
    # Single quotes inside double quotes don't affect double quote tracking
    refute Rubish::Builtins.has_unclosed_quotes(%{x="it's fine"})
  end

  def test_has_unclosed_quotes_escaped_in_double
    # Backslash escapes quote inside double quotes
    # x="hello\" has unclosed quote (backslash escapes the quote)
    assert Rubish::Builtins.has_unclosed_quotes('x="hello\"')
    # x="hello\"" is closed (escaped quote followed by closing quote)
    refute Rubish::Builtins.has_unclosed_quotes('x="hello\""')
  end

  # Test multi-line variable assignments via execute
  def test_multiline_single_quoted_assignment
    execute("X='line1\nline2'")
    assert_equal "line1\nline2", get_shell_var('X')
  end

  def test_multiline_double_quoted_assignment
    execute("X=\"line1\nline2\"")
    assert_equal "line1\nline2", get_shell_var('X')
  end

  def test_multiline_assignment_with_variable_expansion
    set_shell_var('NAME', 'World')
    execute("MSG=\"Hello\n\$NAME\"")
    assert_equal "Hello\nWorld", get_shell_var('MSG')
  end

  # Test eval with multi-line content
  def test_eval_multiline_commands
    output = capture_stdout do
      execute("eval 'echo first\necho second'")
    end
    assert_equal "first\nsecond\n", output
  end

  def test_eval_multiline_assignment_and_echo
    execute("X='A=hello\necho \$A'")
    output = capture_stdout do
      execute('eval "$X"')
    end
    assert_equal "hello\n", output
    assert_equal 'hello', get_shell_var('A')
  end

  def test_eval_rbenv_style_output
    # Simulate rbenv sh-shell output format
    execute("CMD='RBENV_VERSION_OLD=\"\${RBENV_VERSION-}\"\nexport RBENV_VERSION=\"2.7.8\"'")
    set_shell_var('RBENV_VERSION', 'ruby-dev')
    execute('eval "$CMD"')
    assert_equal '2.7.8', get_shell_var('RBENV_VERSION')
    assert_equal 'ruby-dev', get_shell_var('RBENV_VERSION_OLD')
  end

  # Test command substitution with multi-line output used in eval
  def test_eval_command_substitution_multiline
    # Create a script that outputs multi-line content
    script = File.join(@tempdir, 'output_script.sh')
    File.write(script, "#!/bin/sh\necho 'echo line1'\necho 'echo line2'")
    File.chmod(0o755, script)

    output = capture_stdout do
      execute("eval \"$(#{script})\"")
    end
    assert_equal "line1\nline2\n", output
  end

  # Test multi-line strings in script files via run_source
  def test_source_multiline_assignment
    File.write(script_file, <<~'SCRIPT')
      X='line1
      line2'
    SCRIPT

    Rubish::Builtins.source([script_file])
    assert_equal "line1\nline2", get_shell_var('X')
  end

  def test_source_multiline_double_quoted
    File.write(script_file, <<~'SCRIPT')
      NAME=World
      MSG="Hello
      $NAME"
    SCRIPT

    Rubish::Builtins.source([script_file])
    assert_equal "Hello\nWorld", get_shell_var('MSG')
  end

  def test_source_multiline_with_commands
    File.write(script_file, <<~'SCRIPT')
      X='echo hello
      echo world'
      eval "$X"
    SCRIPT

    output = capture_stdout do
      Rubish::Builtins.source([script_file])
    end
    assert_equal "hello\nworld\n", output
  end

  def test_source_multiline_in_function
    # Test multi-line string assigned to shell var inside function
    File.write(script_file, <<~'SCRIPT')
      myfunc() {
        X='line1
      line2'
        echo "$X"
      }
      myfunc
    SCRIPT

    output = capture_stdout do
      Rubish::Builtins.source([script_file])
    end
    assert_equal "line1\nline2\n", output
  end

  def test_source_rbenv_style_function
    # Simulate how rbenv shell function works
    File.write(script_file, <<~'SCRIPT')
      RBENV_VERSION=ruby-dev
      rbenv() {
        local command="${1:-}"
        if [ "$command" = "shell" ]; then
          eval 'RBENV_VERSION_OLD="${RBENV_VERSION-}"
      export RBENV_VERSION="2.7.8"'
        fi
      }
      rbenv shell
    SCRIPT

    Rubish::Builtins.source([script_file])
    assert_equal '2.7.8', get_shell_var('RBENV_VERSION')
    assert_equal 'ruby-dev', get_shell_var('RBENV_VERSION_OLD')
  end

  # Test edge cases
  def test_empty_lines_in_multiline_string
    execute("X='line1\n\nline3'")
    assert_equal "line1\n\nline3", get_shell_var('X')
  end

  def test_multiline_string_with_special_chars
    # Test with tab character (Ruby \t becomes actual tab)
    execute("X='hello\n\tworld\n!'")
    assert_equal "hello\n\tworld\n!", get_shell_var('X')
  end

  def test_multiline_string_with_quotes_inside
    execute("X='line1\nline2 with \"quotes\"'")
    assert_equal "line1\nline2 with \"quotes\"", get_shell_var('X')
  end

  def test_consecutive_multiline_assignments
    File.write(script_file, <<~'SCRIPT')
      A='first
      line'
      B='second
      line'
    SCRIPT

    Rubish::Builtins.source([script_file])
    assert_equal "first\nline", get_shell_var('A')
    assert_equal "second\nline", get_shell_var('B')
  end

  # Test that array assignment VAR=() is not detected as function definition
  def test_source_array_assignment_not_function
    File.write(script_file, <<~'SCRIPT')
      myfunc() {
        MYARRAY=()
        MYARRAY+=(one two)
        echo "${MYARRAY[@]}"
      }
      myfunc
    SCRIPT

    stderr = capture_stderr do
      output = capture_stdout do
        Rubish::Builtins.source([script_file])
      end
      assert_equal "one two\n", output
    end
    # Should NOT have unclosed structure warning
    refute_match(/unclosed/, stderr)
  end

  # Test unclosed quote warning
  def test_source_unclosed_quote_warning
    File.write(script_file, "X='unclosed")

    stderr = capture_stderr do
      Rubish::Builtins.source([script_file])
    end
    assert_match(/unclosed quote/, stderr)
  end
end
