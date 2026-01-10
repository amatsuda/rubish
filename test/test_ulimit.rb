# frozen_string_literal: true

require_relative 'test_helper'

class TestUlimit < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_ulimit_test')
    # Save original limits we might modify
    @original_nofile = Process.getrlimit(Process::RLIMIT_NOFILE)
  end

  def teardown
    # Restore original limits
    Process.setrlimit(Process::RLIMIT_NOFILE, *@original_nofile)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test ulimit is a builtin
  def test_ulimit_is_builtin
    assert Rubish::Builtins.builtin?('ulimit')
  end

  # Test ulimit displays file size limit by default
  def test_ulimit_default_shows_file_size
    output = capture_output { Rubish::Builtins.run('ulimit', []) }
    # Should output a number or 'unlimited'
    assert_match(/^\d+$|^unlimited$/, output.strip)
  end

  # Test ulimit -n shows open files
  def test_ulimit_n_shows_open_files
    output = capture_output { Rubish::Builtins.run('ulimit', ['-n']) }
    soft, _hard = Process.getrlimit(Process::RLIMIT_NOFILE)
    if soft == Process::RLIM_INFINITY
      assert_equal "unlimited\n", output
    else
      assert_equal "#{soft}\n", output
    end
  end

  # Test ulimit -Hn shows hard limit
  def test_ulimit_Hn_shows_hard_limit
    output = capture_output { Rubish::Builtins.run('ulimit', ['-Hn']) }
    _soft, hard = Process.getrlimit(Process::RLIMIT_NOFILE)
    if hard == Process::RLIM_INFINITY
      assert_equal "unlimited\n", output
    else
      assert_equal "#{hard}\n", output
    end
  end

  # Test ulimit -a shows all limits
  def test_ulimit_a_shows_all
    output = capture_output { Rubish::Builtins.run('ulimit', ['-a']) }
    # Should show multiple lines with resource descriptions
    assert_match(/open files/, output)
    assert_match(/stack size/, output)
    lines = output.strip.split("\n")
    assert lines.length > 5
  end

  # Test ulimit -n can set limit
  def test_ulimit_n_sets_limit
    soft, hard = Process.getrlimit(Process::RLIMIT_NOFILE)
    new_limit = [256, soft, hard].min  # Pick a safe value

    result = Rubish::Builtins.run('ulimit', ['-n', new_limit.to_s])
    assert result

    new_soft, _new_hard = Process.getrlimit(Process::RLIMIT_NOFILE)
    assert_equal new_limit, new_soft
  end

  # Test ulimit with unlimited
  def test_ulimit_set_unlimited
    # This may fail without root, so just test the parsing
    output = capture_output do
      Rubish::Builtins.run('ulimit', ['-n', 'unlimited'])
    end
    # Either succeeds silently, fails with permission error, or invalid limit (some resources don't support unlimited)
    assert_match(/^$|cannot modify|invalid limit/, output)
  end

  # Test ulimit -t shows CPU time
  def test_ulimit_t_shows_cpu_time
    output = capture_output { Rubish::Builtins.run('ulimit', ['-t']) }
    assert_match(/^\d+$|^unlimited$/, output.strip)
  end

  # Test ulimit -s shows stack size
  def test_ulimit_s_shows_stack_size
    output = capture_output { Rubish::Builtins.run('ulimit', ['-s']) }
    assert_match(/^\d+$|^unlimited$/, output.strip)
  end

  # Test ulimit -v shows virtual memory
  def test_ulimit_v_shows_virtual_memory
    output = capture_output { Rubish::Builtins.run('ulimit', ['-v']) }
    assert_match(/^\d+$|^unlimited$/, output.strip)
  end

  # Test ulimit with invalid option
  def test_ulimit_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('ulimit', ['-z'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test ulimit with invalid value
  def test_ulimit_invalid_value
    output = capture_output do
      result = Rubish::Builtins.run('ulimit', ['-n', 'notanumber'])
      assert_false result
    end
    assert_match(/invalid limit/, output)
  end

  # Test type identifies ulimit as builtin
  def test_type_identifies_ulimit_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['ulimit']) }
    assert_match(/ulimit is a shell builtin/, output)
  end

  # Test ulimit via REPL
  def test_ulimit_via_repl
    output = capture_output { execute('ulimit -n') }
    assert_match(/^\d+$|^unlimited$/, output.strip)
  end

  # Test ulimit -Ha shows hard limits for all
  def test_ulimit_Ha_shows_hard_limits
    output = capture_output { Rubish::Builtins.run('ulimit', ['-Ha']) }
    assert_match(/open files/, output)
    lines = output.strip.split("\n")
    assert lines.length > 5
  end
end
