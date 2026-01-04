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
    assert_equal 'INT', sig  # Signal 2 is INT
  end

  def test_normalize_signal_numeric_exit
    sig = Rubish::Builtins.normalize_signal('0')
    assert_equal 0, sig  # Signal 0 is EXIT
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

  # Tests for new signals
  def test_trap_pipe_signal
    Rubish::Builtins.run('trap', ['echo pipe', 'PIPE'])
    assert_equal 'echo pipe', Rubish::Builtins.traps['PIPE']
  end

  def test_trap_abrt_signal
    Rubish::Builtins.run('trap', ['echo abort', 'ABRT'])
    assert_equal 'echo abort', Rubish::Builtins.traps['ABRT']
  end

  def test_trap_iot_alias
    # IOT is an alias for ABRT
    sig = Rubish::Builtins.normalize_signal('IOT')
    assert_equal 'ABRT', sig
  end

  def test_trap_numeric_15
    # Signal 15 is TERM
    sig = Rubish::Builtins.normalize_signal('15')
    assert_equal 'TERM', sig
  end

  def test_trap_numeric_signals_various
    assert_equal 'HUP', Rubish::Builtins.normalize_signal('1')
    assert_equal 'QUIT', Rubish::Builtins.normalize_signal('3')
    assert_equal 'KILL', Rubish::Builtins.normalize_signal('9')
    assert_equal 'PIPE', Rubish::Builtins.normalize_signal('13')
    assert_equal 'USR1', Rubish::Builtins.normalize_signal('30')
    assert_equal 'USR2', Rubish::Builtins.normalize_signal('31')
  end

  def test_trap_kill_cannot_be_trapped
    output = capture_output { Rubish::Builtins.run('trap', ['echo kill', 'KILL']) }
    assert_match(/cannot be trapped/, output)
    assert_nil Rubish::Builtins.traps['KILL']
  end

  def test_trap_stop_cannot_be_trapped
    output = capture_output { Rubish::Builtins.run('trap', ['echo stop', 'STOP']) }
    assert_match(/cannot be trapped/, output)
    assert_nil Rubish::Builtins.traps['STOP']
  end

  def test_trap_list_format
    output = capture_output { Rubish::Builtins.run('trap', ['-l']) }
    # Should show signals in bash-like format: " 1) HUP  2) INT ..."
    assert_match(/\d+\)\s+\w+/, output)
    assert_match(/HUP/, output)
    assert_match(/PIPE/, output)
    assert_match(/USR1/, output)
  end

  def test_trap_xcpu_signal
    Rubish::Builtins.run('trap', ['echo cpu', 'XCPU'])
    assert_equal 'echo cpu', Rubish::Builtins.traps['XCPU']
  end

  def test_trap_xfsz_signal
    Rubish::Builtins.run('trap', ['echo fsz', 'XFSZ'])
    assert_equal 'echo fsz', Rubish::Builtins.traps['XFSZ']
  end

  def test_trap_winch_signal
    Rubish::Builtins.run('trap', ['echo winch', 'WINCH'])
    assert_equal 'echo winch', Rubish::Builtins.traps['WINCH']
  end

  def test_trap_info_signal
    Rubish::Builtins.run('trap', ['echo info', 'INFO'])
    assert_equal 'echo info', Rubish::Builtins.traps['INFO']
  end

  def test_trap_chld_alias
    # CLD is an alias for CHLD
    sig = Rubish::Builtins.normalize_signal('CLD')
    assert_equal 'CHLD', sig
  end

  def test_trap_io_poll_alias
    # POLL is an alias for IO
    sig = Rubish::Builtins.normalize_signal('POLL')
    assert_equal 'IO', sig
  end
end
