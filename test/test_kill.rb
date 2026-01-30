# frozen_string_literal: true

require_relative 'test_helper'

class TestKill < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_kill_test')
    Rubish::JobManager.instance.clear
    # Enable monitor mode for job tracking
    Rubish::Builtins.current_state.set_options['m'] = true
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::JobManager.instance.clear
    Rubish::Builtins.current_state.set_options['m'] = false
  end

  # Test kill is a builtin
  def test_kill_is_builtin
    assert Rubish::Builtins.builtin?('kill')
  end

  # Test kill -l lists signals
  def test_kill_list_signals
    output = capture_output { Rubish::Builtins.run('kill', ['-l']) }
    assert_match(/SIGTERM/, output)
    assert_match(/SIGINT/, output)
    assert_match(/SIGKILL/, output)
  end

  # Test kill -l converts number to name
  def test_kill_l_number_to_name
    output = capture_output { Rubish::Builtins.run('kill', ['-l', '9']) }
    assert_match(/KILL/, output)
  end

  # Test kill -l converts name to number
  def test_kill_l_name_to_number
    output = capture_output { Rubish::Builtins.run('kill', ['-l', 'TERM']) }
    assert_match(/15/, output)
  end

  # Test kill with no args shows usage
  def test_kill_no_args
    output = capture_output { Rubish::Builtins.run('kill', []) }
    assert_match(/usage/, output)
  end

  # Test kill invalid job spec
  def test_kill_invalid_job_spec
    output = capture_output do
      result = Rubish::Builtins.run('kill', ['%999'])
      assert_false result
    end
    assert_match(/no such job/, output)
  end

  # Test kill nonexistent pid
  def test_kill_nonexistent_pid
    output = capture_output do
      result = Rubish::Builtins.run('kill', ['999999'])
      assert_false result
    end
    assert_match(/No such process/, output)
  end

  # Test kill invalid signal
  def test_kill_invalid_signal
    output = capture_output do
      result = Rubish::Builtins.run('kill', ['-s', 'INVALID', '123'])
      assert_false result
    end
    assert_match(/invalid signal/, output)
  end

  # Test type identifies kill as builtin
  def test_type_identifies_kill_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['kill']) }
    assert_match(/kill is a shell builtin/, output)
  end

  # Test kill with -SIGNAL syntax
  def test_kill_signal_syntax
    # Start a sleep process
    pid = spawn('sleep', '10')
    # Kill it with -TERM
    result = Rubish::Builtins.run('kill', ['-TERM', pid.to_s])
    assert result
    # Clean up
    Process.wait(pid)
  end

  # Test kill with -s SIGNAL syntax
  def test_kill_s_signal_syntax
    pid = spawn('sleep', '10')
    result = Rubish::Builtins.run('kill', ['-s', 'TERM', pid.to_s])
    assert result
    Process.wait(pid)
  end

  # Test kill with signal number
  def test_kill_signal_number
    pid = spawn('sleep', '10')
    result = Rubish::Builtins.run('kill', ['-15', pid.to_s])
    assert result
    Process.wait(pid)
  end

  # Test kill background job
  def test_kill_background_job
    execute('sleep 10 &')
    manager = Rubish::JobManager.instance
    job = manager.last
    assert_not_nil job

    result = Rubish::Builtins.run('kill', ['%1'])
    assert result

    # Wait for job to be killed
    sleep 0.1
    manager.check_background_jobs
  end
end
