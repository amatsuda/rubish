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

  # set -u (nounset)
  def test_set_minus_u_enables_nounset
    execute('set -u')
    assert Rubish::Builtins.set_option?('u')
  end

  def test_set_plus_u_disables_nounset
    execute('set -u')
    execute('set +u')
    assert_false Rubish::Builtins.set_option?('u')
  end

  def test_set_o_nounset
    execute('set -o nounset')
    assert Rubish::Builtins.set_option?('u')
  end

  def test_nounset_error_on_unset_variable
    execute('set -u')
    stderr_file = File.join(@tempdir, 'stderr.txt')
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')
    begin
      # This should print an error to stderr
      catch(:exit) { execute("echo $UNSET_VAR_FOR_TEST > #{output_file}") }
    ensure
      $stderr.close
      $stderr = old_stderr
    end
    execute('set +u')

    stderr_content = File.read(stderr_file)
    assert_match(/UNSET_VAR_FOR_TEST.*unbound variable/, stderr_content)
  end

  def test_nounset_no_error_on_set_variable
    ENV['NOUNSET_TEST_VAR'] = 'hello'
    execute('set -u')
    execute("echo $NOUNSET_TEST_VAR > #{output_file}")
    execute('set +u')
    assert_equal "hello\n", File.read(output_file)
  ensure
    ENV.delete('NOUNSET_TEST_VAR')
  end

  def test_nounset_no_error_on_empty_variable
    # Empty variables are considered "set" even if empty
    ENV['NOUNSET_EMPTY_VAR'] = ''
    execute('set -u')
    execute("echo \"x${NOUNSET_EMPTY_VAR}y\" > #{output_file}")
    execute('set +u')
    assert_equal "xy\n", File.read(output_file)
  ensure
    ENV.delete('NOUNSET_EMPTY_VAR')
  end

  def test_nounset_special_vars_always_set
    # Special variables like $?, $$, $# should work even with nounset
    execute('set -u')
    execute("echo $? > #{output_file}")
    result = File.read(output_file).chomp
    execute('set +u')
    assert_match(/^\d+$/, result)
  end

  # set -f (noglob)
  def test_set_minus_f_enables_noglob
    execute('set -f')
    assert Rubish::Builtins.set_option?('f')
  end

  def test_set_plus_f_disables_noglob
    execute('set -f')
    execute('set +f')
    assert_false Rubish::Builtins.set_option?('f')
  end

  def test_set_o_noglob
    execute('set -o noglob')
    assert Rubish::Builtins.set_option?('f')
  end

  def test_noglob_prevents_glob_expansion
    # Create test files
    File.write(File.join(@tempdir, 'test1.txt'), 'a')
    File.write(File.join(@tempdir, 'test2.txt'), 'b')

    # Without noglob, *.txt should expand
    execute("echo #{@tempdir}/*.txt > #{output_file}")
    without_noglob = File.read(output_file).chomp

    # With noglob, *.txt should NOT expand
    execute('set -f')
    execute("echo #{@tempdir}/*.txt > #{output_file}")
    with_noglob = File.read(output_file).chomp
    execute('set +f')

    # Without noglob should have expanded to actual files
    assert_match(/test1\.txt/, without_noglob)
    assert_match(/test2\.txt/, without_noglob)

    # With noglob should have the literal *.txt
    assert_match(/\*\.txt/, with_noglob)
  end

  def test_noglob_preserves_question_mark
    execute('set -f')
    execute("echo test?.txt > #{output_file}")
    result = File.read(output_file).chomp
    execute('set +f')

    assert_equal 'test?.txt', result
  end

  def test_noglob_preserves_brackets
    execute('set -f')
    execute("echo test[123].txt > #{output_file}")
    result = File.read(output_file).chomp
    execute('set +f')

    assert_equal 'test[123].txt', result
  end

  # Other options (should at least not error)

  def test_set_minus_C_noclobber
    execute('set -C')
    assert Rubish::Builtins.set_option?('C')
  end
end
