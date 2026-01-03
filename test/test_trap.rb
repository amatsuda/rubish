# frozen_string_literal: true

require_relative 'test_helper'

class TestTrap < Test::Unit::TestCase
  def setup
    Rubish::Builtins.clear_traps
  end

  def teardown
    Rubish::Builtins.clear_traps
  end

  def test_trap_set_command
    Rubish::Builtins.run('trap', ['echo trapped', 'INT'])
    assert_equal({'INT' => 'echo trapped'}, Rubish::Builtins.traps)
  end

  def test_trap_set_multiple_signals
    Rubish::Builtins.run('trap', ['echo handler', 'INT', 'TERM'])
    assert_equal 'echo handler', Rubish::Builtins.traps['INT']
    assert_equal 'echo handler', Rubish::Builtins.traps['TERM']
  end

  def test_trap_with_sig_prefix
    Rubish::Builtins.run('trap', ['echo sig', 'SIGINT'])
    assert_equal({'INT' => 'echo sig'}, Rubish::Builtins.traps)
  end

  def test_trap_ignore_signal
    Rubish::Builtins.run('trap', ['', 'INT'])
    assert_equal({'INT' => ''}, Rubish::Builtins.traps)
  end

  def test_trap_reset_signal
    Rubish::Builtins.run('trap', ['echo handler', 'USR1'])
    Rubish::Builtins.run('trap', ['-', 'USR1'])
    assert_equal({}, Rubish::Builtins.traps)
  end

  def test_trap_exit
    Rubish::Builtins.run('trap', ['echo goodbye', 'EXIT'])
    assert_equal({0 => 'echo goodbye'}, Rubish::Builtins.traps)
  end

  def test_trap_list
    Rubish::Builtins.run('trap', ['echo int', 'INT'])
    output = capture_output { Rubish::Builtins.run('trap', []) }
    assert_match(/trap -- "echo int" INT/, output)
  end

  def test_trap_list_signals
    output = capture_output { Rubish::Builtins.run('trap', ['-l']) }
    assert_match(/INT/, output)
    assert_match(/TERM/, output)
  end

  def test_trap_print_specific
    Rubish::Builtins.run('trap', ['echo int', 'INT'])
    Rubish::Builtins.run('trap', ['echo term', 'TERM'])
    output = capture_output { Rubish::Builtins.run('trap', ['-p', 'INT']) }
    assert_match(/echo int/, output)
    assert_no_match(/echo term/, output)
  end

  def test_trap_invalid_signal
    output = capture_output { Rubish::Builtins.run('trap', ['echo', 'INVALID']) }
    assert_match(/invalid signal/, output)
  end

  def test_trap_no_args
    output = capture_output { result = Rubish::Builtins.run('trap', []) }
    # No error, just lists traps (empty)
    assert_equal '', output
  end

  def test_trap_usage_error
    output = capture_output { Rubish::Builtins.run('trap', ['echo']) }
    assert_match(/usage/, output)
  end

  def test_trap_overwrite
    Rubish::Builtins.run('trap', ['echo first', 'USR1'])
    Rubish::Builtins.run('trap', ['echo second', 'USR1'])
    assert_equal({'USR1' => 'echo second'}, Rubish::Builtins.traps)
  end

  def test_normalize_signal_numeric
    sig = Rubish::Builtins.normalize_signal('2')
    assert_equal 2, sig
  end

  def test_normalize_signal_name
    sig = Rubish::Builtins.normalize_signal('INT')
    assert_equal 'INT', sig
  end

  def test_normalize_signal_with_sig_prefix
    sig = Rubish::Builtins.normalize_signal('SIGTERM')
    assert_equal 'TERM', sig
  end

  def test_normalize_signal_lowercase
    sig = Rubish::Builtins.normalize_signal('int')
    assert_equal 'INT', sig
  end
end
