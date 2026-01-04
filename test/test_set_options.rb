# frozen_string_literal: true

require_relative 'test_helper'

class TestSetOptions < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_set_options_test')
    @saved_env = ENV.to_h
    # Reset all set options to defaults
    reset_set_options
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
    reset_set_options
  end

  def reset_set_options
    Rubish::Builtins.set_options.each_key { |k| Rubish::Builtins.set_options[k] = false }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # set -e (errexit)
  def test_set_minus_e_enables_errexit
    execute('set -e')
    assert Rubish::Builtins.set_option?('e')
  end

  def test_set_plus_e_disables_errexit
    execute('set -e')
    execute('set +e')
    assert_false Rubish::Builtins.set_option?('e')
  end

  def test_set_o_errexit
    execute('set -o errexit')
    assert Rubish::Builtins.set_option?('e')
  end

  def test_set_plus_o_errexit
    execute('set -o errexit')
    execute('set +o errexit')
    assert_false Rubish::Builtins.set_option?('e')
  end

  # set -x (xtrace)
  def test_set_minus_x_enables_xtrace
    execute('set -x')
    assert Rubish::Builtins.set_option?('x')
  end

  def test_set_plus_x_disables_xtrace
    execute('set -x')
    execute('set +x')
    assert_false Rubish::Builtins.set_option?('x')
  end

  def test_set_o_xtrace
    execute('set -o xtrace')
    assert Rubish::Builtins.set_option?('x')
  end

  # Multiple options
  def test_set_multiple_options
    execute('set -ex')
    assert Rubish::Builtins.set_option?('e')
    assert Rubish::Builtins.set_option?('x')
  end

  def test_disable_multiple_options
    execute('set -ex')
    execute('set +ex')
    assert_false Rubish::Builtins.set_option?('e')
    assert_false Rubish::Builtins.set_option?('x')
  end

  # xtrace output
  def test_xtrace_prints_to_stderr
    stderr_file = File.join(@tempdir, 'stderr.txt')
    execute('set -x')
    # Capture stderr
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')
    begin
      execute("echo hello > #{output_file}")
    ensure
      $stderr.close
      $stderr = old_stderr
    end
    execute('set +x')

    stderr_content = File.read(stderr_file)
    assert_match(/\+ echo hello/, stderr_content)
  end

  def test_xtrace_uses_ps4
    stderr_file = File.join(@tempdir, 'stderr.txt')
    ENV['PS4'] = '>>> '
    execute('set -x')
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')
    begin
      execute("echo test > #{output_file}")
    ensure
      $stderr.close
      $stderr = old_stderr
    end
    execute('set +x')

    stderr_content = File.read(stderr_file)
    assert_match(/^>>> echo test/, stderr_content)
  end

  # set -o (list options)
  def test_set_minus_o_lists_options
    output = capture_stdout { execute('set -o') }
    assert_match(/errexit/, output)
    assert_match(/xtrace/, output)
  end

  def test_set_plus_o_lists_options
    output = capture_stdout { execute('set +o') }
    assert_match(/errexit/, output)
    assert_match(/xtrace/, output)
  end

  def test_set_o_shows_enabled_options
    execute('set -e')
    output = capture_stdout { execute('set -o') }
    assert_match(/set -o errexit/, output)
  end

  def test_set_o_shows_disabled_options
    output = capture_stdout { execute('set -o') }
    assert_match(/set \+o errexit/, output)
  end

  # Other options (should at least not error)
  def test_set_minus_u_nounset
    execute('set -u')
    assert Rubish::Builtins.set_option?('u')
  end

  def test_set_minus_f_noglob
    execute('set -f')
    assert Rubish::Builtins.set_option?('f')
  end

  def test_set_minus_C_noclobber
    execute('set -C')
    assert Rubish::Builtins.set_option?('C')
  end
end
