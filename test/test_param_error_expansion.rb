# frozen_string_literal: true

require_relative 'test_helper'

# ${VAR:?msg} / ${VAR?msg}: report the error like bash instead of raising a
# bare RuntimeError. A non-interactive shell exits with 127; an interactive
# one prints the message and continues with status 1.
class TestParamErrorExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @was_interactive = Rubish::Builtins.interactive_mode?
    Rubish::Builtins.current_state.set_options['i'] = false
    Rubish::Builtins.unset(['RUBISH_PE_UNSET'])
  end

  def teardown
    Rubish::Builtins.current_state.set_options['i'] = @was_interactive
    Rubish::Builtins.unset(%w[RUBISH_PE_UNSET RUBISH_PE_SET])
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_unset_with_message_prints_name_and_message
    err = capture_stderr { catch(:exit) { execute('echo "${RUBISH_PE_UNSET:?custom message}"') } }
    assert_equal "rubish: RUBISH_PE_UNSET: custom message\n", err
  end

  def test_unset_without_message_prints_default_message
    err = capture_stderr { catch(:exit) { execute('echo "${RUBISH_PE_UNSET:?}"') } }
    assert_equal "rubish: RUBISH_PE_UNSET: parameter null or not set\n", err
  end

  def test_non_interactive_shell_exits_with_127
    exit_code = capture_stderr_and_catch_exit { execute('echo "${RUBISH_PE_UNSET:?}"; echo not_reached') }
    assert_equal 127, exit_code
  end

  def test_interactive_shell_continues_with_status_1
    Rubish::Builtins.current_state.set_options['i'] = true
    out = capture_output { execute('echo "${RUBISH_PE_UNSET:?}"') }
    assert_match(/parameter null or not set/, out)
    assert_equal 1, last_status
  end

  def test_set_variable_expands_normally
    execute('RUBISH_PE_SET=hello')
    out = capture_stdout { execute('echo "${RUBISH_PE_SET:?}"') }
    assert_equal "hello\n", out
  end

  def test_unquoted_form_null_allowed_with_plain_question_mark
    execute('RUBISH_PE_SET=')
    out = capture_output { execute('echo "[${RUBISH_PE_SET?msg}]"') }
    assert_equal "[]\n", out
  end

  private

  def capture_stderr_and_catch_exit
    result = nil
    capture_stderr { result = catch(:exit) { yield; :no_exit } }
    result
  end
end
