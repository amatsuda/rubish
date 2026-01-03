# frozen_string_literal: true

require_relative 'test_helper'

class TestLogout < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @saved_stderr = $stderr
    # Save shell options state
    @saved_shell_options = Rubish::Builtins.shell_options.dup
  end

  def teardown
    $stderr = @saved_stderr
    # Restore shell options
    Rubish::Builtins.instance_variable_set(:@shell_options, @saved_shell_options)
  end

  # Basic tests
  def test_logout_is_builtin
    assert Rubish::Builtins.builtin?('logout')
  end

  def test_logout_in_commands_list
    assert_include Rubish::Builtins::COMMANDS, 'logout'
  end

  # Exit behavior tests
  def test_logout_throws_exit
    assert_throw(:exit) do
      Rubish::Builtins.run_logout([])
    end
  end

  def test_logout_exits_with_zero_by_default
    exit_code = catch(:exit) do
      Rubish::Builtins.run_logout([])
    end
    assert_equal 0, exit_code
  end

  def test_logout_exits_with_specified_code
    exit_code = catch(:exit) do
      Rubish::Builtins.run_logout(['42'])
    end
    assert_equal 42, exit_code
  end

  def test_logout_exits_with_negative_code
    exit_code = catch(:exit) do
      Rubish::Builtins.run_logout(['-1'])
    end
    assert_equal(-1, exit_code)
  end

  # Login shell warning tests
  def test_logout_warns_when_not_login_shell
    Rubish::Builtins.shell_options['login_shell'] = false

    output = capture_stderr do
      catch(:exit) { Rubish::Builtins.run_logout([]) }
    end

    assert_match(/not login shell/, output)
    assert_match(/use `exit'/, output)
  end

  def test_logout_no_warning_when_login_shell
    Rubish::Builtins.shell_options['login_shell'] = true

    output = capture_stderr do
      catch(:exit) { Rubish::Builtins.run_logout([]) }
    end

    assert_equal '', output
  end

  def test_logout_still_exits_when_not_login_shell
    Rubish::Builtins.shell_options['login_shell'] = false

    $stderr = StringIO.new  # Suppress warning
    exit_code = catch(:exit) do
      Rubish::Builtins.run_logout(['5'])
    end

    assert_equal 5, exit_code
  end

  # Exit traps
  def test_logout_runs_exit_traps
    trap_executed = false
    Rubish::Builtins.traps[0] = 'echo trap'

    # Mock the executor to track trap execution
    original_executor = Rubish::Builtins.executor
    Rubish::Builtins.executor = ->(cmd) { trap_executed = true if cmd == 'echo trap' }

    $stderr = StringIO.new  # Suppress any warnings
    catch(:exit) { Rubish::Builtins.run_logout([]) }

    assert_true trap_executed
  ensure
    Rubish::Builtins.executor = original_executor
    Rubish::Builtins.traps.delete(0)
  end

  # Integration with run method
  def test_logout_via_run
    exit_code = catch(:exit) do
      Rubish::Builtins.run('logout', ['0'])
    end
    assert_equal 0, exit_code
  end

  def test_logout_via_run_with_code
    exit_code = catch(:exit) do
      Rubish::Builtins.run('logout', ['99'])
    end
    assert_equal 99, exit_code
  end
end
