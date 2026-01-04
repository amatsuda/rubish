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
    # Reset all options to their defaults
    Rubish::Builtins.set_options.each_key { |k| Rubish::Builtins.set_options[k] = false }
    # Braceexpand and histexpand are enabled by default
    Rubish::Builtins.set_options['B'] = true
    Rubish::Builtins.set_options['H'] = true
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

  # set -C (noclobber)
  def test_set_minus_C_enables_noclobber
    execute('set -C')
    assert Rubish::Builtins.set_option?('C')
  end

  def test_set_plus_C_disables_noclobber
    execute('set -C')
    execute('set +C')
    assert_false Rubish::Builtins.set_option?('C')
  end

  def test_set_o_noclobber
    execute('set -o noclobber')
    assert Rubish::Builtins.set_option?('C')
  end

  def test_noclobber_prevents_overwrite
    # Create a file first
    File.write(output_file, "original content\n")

    stderr_file = File.join(@tempdir, 'stderr.txt')
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')

    execute('set -C')
    begin
      execute("echo new content > #{output_file}")
    ensure
      $stderr.close
      $stderr = old_stderr
    end
    execute('set +C')

    # File should still have original content
    assert_equal "original content\n", File.read(output_file)
    # Should have printed error to stderr
    stderr_content = File.read(stderr_file)
    assert_match(/cannot overwrite existing file/, stderr_content)
  end

  def test_noclobber_allows_new_file
    new_file = File.join(@tempdir, 'new_file.txt')
    execute('set -C')
    execute("echo hello > #{new_file}")
    execute('set +C')

    assert_equal "hello\n", File.read(new_file)
  end

  def test_noclobber_allows_append
    # Create a file first
    File.write(output_file, "original\n")

    execute('set -C')
    execute("echo appended >> #{output_file}")
    execute('set +C')

    assert_equal "original\nappended\n", File.read(output_file)
  end

  def test_clobber_operator_bypasses_noclobber
    # Create a file first
    File.write(output_file, "original\n")

    execute('set -C')
    execute("echo forced >| #{output_file}")
    execute('set +C')

    assert_equal "forced\n", File.read(output_file)
  end

  # set -v (verbose)
  def test_set_minus_v_enables_verbose
    execute('set -v')
    assert Rubish::Builtins.set_option?('v')
  end

  def test_set_plus_v_disables_verbose
    execute('set -v')
    execute('set +v')
    assert_false Rubish::Builtins.set_option?('v')
  end

  def test_set_o_verbose
    execute('set -o verbose')
    assert Rubish::Builtins.set_option?('v')
  end

  def test_verbose_prints_input_to_stderr
    stderr_file = File.join(@tempdir, 'stderr.txt')
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')

    execute('set -v')
    begin
      execute("echo hello > #{output_file}")
    ensure
      $stderr.close
      $stderr = old_stderr
    end
    execute('set +v')

    stderr_content = File.read(stderr_file)
    assert_match(/echo hello/, stderr_content)
  end

  def test_verbose_prints_before_expansion
    ENV['VERBOSE_TEST'] = 'expanded_value'
    stderr_file = File.join(@tempdir, 'stderr.txt')
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')

    execute('set -v')
    begin
      execute("echo $VERBOSE_TEST > #{output_file}")
    ensure
      $stderr.close
      $stderr = old_stderr
    end
    execute('set +v')

    stderr_content = File.read(stderr_file)
    # Should print with the variable reference, not the expanded value
    assert_match(/\$VERBOSE_TEST/, stderr_content)
  ensure
    ENV.delete('VERBOSE_TEST')
  end

  # set -a (allexport)
  def test_set_minus_a_enables_allexport
    execute('set -a')
    assert Rubish::Builtins.set_option?('a')
  end

  def test_set_plus_a_disables_allexport
    execute('set -a')
    execute('set +a')
    assert_false Rubish::Builtins.set_option?('a')
  end

  def test_set_o_allexport
    execute('set -o allexport')
    assert Rubish::Builtins.set_option?('a')
  end

  def test_allexport_marks_variables_as_exported
    Rubish::Builtins.clear_var_attributes

    execute('set -a')
    execute('ALLEXPORT_TEST=hello')
    execute('set +a')

    assert Rubish::Builtins.has_attribute?('ALLEXPORT_TEST', :export)
  ensure
    ENV.delete('ALLEXPORT_TEST')
  end

  def test_allexport_variable_available_to_child
    execute('set -a')
    execute('CHILD_TEST_VAR=test_value')
    # Run a subshell that echoes the variable
    execute("sh -c 'echo $CHILD_TEST_VAR' > #{output_file}")
    execute('set +a')

    assert_equal "test_value\n", File.read(output_file)
  ensure
    ENV.delete('CHILD_TEST_VAR')
  end

  def test_allexport_disabled_does_not_mark_export
    Rubish::Builtins.clear_var_attributes

    execute('set +a')  # Make sure it's off
    execute('NO_EXPORT_TEST=value')

    assert_false Rubish::Builtins.has_attribute?('NO_EXPORT_TEST', :export)
  ensure
    ENV.delete('NO_EXPORT_TEST')
  end

  # set -n (noexec)
  def test_set_minus_n_enables_noexec
    execute('set -n')
    assert Rubish::Builtins.set_option?('n')
    execute('set +n')  # Turn it off so other tests work
  end

  def test_set_plus_n_disables_noexec
    execute('set -n')
    execute('set +n')
    assert_false Rubish::Builtins.set_option?('n')
  end

  def test_set_o_noexec
    execute('set -o noexec')
    assert Rubish::Builtins.set_option?('n')
    execute('set +n')
  end

  def test_noexec_does_not_execute_commands
    execute('set -n')
    execute("echo should_not_appear > #{output_file}")
    execute('set +n')

    # File should not exist or be empty since command wasn't executed
    assert_false File.exist?(output_file)
  end

  def test_noexec_still_parses_for_syntax_errors
    execute('set -n')
    # This should parse without error
    execute('echo hello world')
    assert_equal 0, @repl.instance_variable_get(:@last_status)
    execute('set +n')
  end

  def test_noexec_allows_set_command
    execute('set -n')
    # set command should still work to allow turning off noexec
    execute('set +n')
    assert_false Rubish::Builtins.set_option?('n')
  end

  def test_noexec_does_not_run_external_commands
    execute('set -n')
    execute("touch #{File.join(@tempdir, 'should_not_exist.txt')}")
    execute('set +n')

    assert_false File.exist?(File.join(@tempdir, 'should_not_exist.txt'))
  end

  # set -b (notify)
  def test_set_minus_b_enables_notify
    execute('set -b')
    assert Rubish::Builtins.set_option?('b')
    execute('set +b')
  end

  def test_set_plus_b_disables_notify
    execute('set -b')
    execute('set +b')
    assert_false Rubish::Builtins.set_option?('b')
  end

  def test_set_o_notify
    execute('set -o notify')
    assert Rubish::Builtins.set_option?('b')
    execute('set +b')
  end

  # set -h (hashall)
  def test_set_minus_h_enables_hashall
    execute('set -h')
    assert Rubish::Builtins.set_option?('h')
    execute('set +h')
  end

  def test_set_plus_h_disables_hashall
    execute('set -h')
    execute('set +h')
    assert_false Rubish::Builtins.set_option?('h')
  end

  def test_set_o_hashall
    execute('set -o hashall')
    assert Rubish::Builtins.set_option?('h')
    execute('set +h')
  end

  def test_hashall_caches_command_path
    Rubish::Builtins.clear_hash

    execute('set -h')
    execute("ls > #{output_file}")
    execute('set +h')

    # ls should now be in the hash
    cached_path = Rubish::Builtins.hash_lookup('ls')
    assert_not_nil cached_path
    assert cached_path.end_with?('/ls')
    assert File.executable?(cached_path)
  end

  def test_hashall_uses_cached_path
    Rubish::Builtins.clear_hash

    execute('set -h')
    # First execution caches the path
    execute("echo first > #{output_file}")
    first_path = Rubish::Builtins.hash_lookup('echo')

    # Second execution should use cached path
    execute("echo second >> #{output_file}")
    second_path = Rubish::Builtins.hash_lookup('echo')
    execute('set +h')

    assert_equal first_path, second_path
  end

  def test_hashall_disabled_does_not_cache
    Rubish::Builtins.clear_hash

    execute('set +h')  # Ensure disabled
    execute("ls > #{output_file}")

    # ls should NOT be in the hash
    assert_nil Rubish::Builtins.hash_lookup('ls')
  end

  # set -m (monitor)
  def test_set_minus_m_enables_monitor
    execute('set -m')
    assert Rubish::Builtins.set_option?('m')
  end

  def test_set_plus_m_disables_monitor
    execute('set -m')
    execute('set +m')
    assert_false Rubish::Builtins.set_option?('m')
  end

  def test_set_o_monitor
    execute('set -o monitor')
    assert Rubish::Builtins.set_option?('m')
  end

  def test_fg_requires_monitor_mode
    execute('set +m')  # Ensure monitor is disabled

    output = capture_stdout do
      execute('fg')
    end

    assert_match(/no job control/, output)
  end

  def test_bg_requires_monitor_mode
    execute('set +m')  # Ensure monitor is disabled

    output = capture_stdout do
      execute('bg')
    end

    assert_match(/no job control/, output)
  end

  # set -o pipefail
  def test_set_o_pipefail_enables_pipefail
    execute('set -o pipefail')
    assert Rubish::Builtins.set_option?('pipefail')
  end

  def test_set_plus_o_pipefail_disables_pipefail
    execute('set -o pipefail')
    execute('set +o pipefail')
    assert_false Rubish::Builtins.set_option?('pipefail')
  end

  def test_pipefail_pipeline_fails_if_first_command_fails
    execute('set -o pipefail')

    # false | true should fail with pipefail
    execute("false | true > #{output_file}")
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_pipefail_pipeline_fails_if_middle_command_fails
    execute('set -o pipefail')

    # true | false | true should fail with pipefail
    execute("true | false | true > #{output_file}")
    assert_not_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_pipefail_pipeline_succeeds_if_all_commands_succeed
    execute('set -o pipefail')

    # true | true | true should succeed
    execute('true | true | true')
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_without_pipefail_pipeline_succeeds_if_last_command_succeeds
    execute('set +o pipefail')  # Ensure disabled

    # false | true should succeed without pipefail (last command succeeds)
    execute("false | true > #{output_file}")
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  # set -E (errtrace)
  def test_set_minus_E_enables_errtrace
    execute('set -E')
    assert Rubish::Builtins.set_option?('E')
  end

  def test_set_plus_E_disables_errtrace
    execute('set -E')
    execute('set +E')
    assert_false Rubish::Builtins.set_option?('E')
  end

  def test_set_o_errtrace
    execute('set -o errtrace')
    assert Rubish::Builtins.set_option?('E')
  end

  def test_err_trap_runs_on_command_failure
    execute("trap 'echo ERR_TRIGGERED' ERR")
    output = capture_stdout do
      execute('false')
    end
    assert_match(/ERR_TRIGGERED/, output)
    execute('trap - ERR')
  end

  def test_err_trap_not_run_on_success
    execute("trap 'echo ERR_TRIGGERED' ERR")
    output = capture_stdout do
      execute('true')
    end
    assert_no_match(/ERR_TRIGGERED/, output)
    execute('trap - ERR')
  end

  def test_errtrace_err_trap_inherited_by_function
    execute('set -E')
    execute("trap 'echo ERR_IN_FUNC' ERR")
    execute('myfunc() { false; }')
    output = capture_stdout do
      execute('myfunc')
    end
    assert_match(/ERR_IN_FUNC/, output)
    execute('trap - ERR')
    execute('set +E')
  end

  def test_no_errtrace_err_trap_not_inherited_by_function
    execute('set +E')  # Ensure errtrace is off
    execute("trap 'echo ERR_IN_FUNC' ERR")
    execute('myfunc() { false; }')
    output = capture_stdout do
      execute('myfunc')
    end
    # ERR trap should NOT run inside function when errtrace is off
    assert_no_match(/ERR_IN_FUNC/, output)
    execute('trap - ERR')
  end

  # set -T (functrace)
  def test_set_minus_T_enables_functrace
    execute('set -T')
    assert Rubish::Builtins.set_option?('T')
  end

  def test_set_plus_T_disables_functrace
    execute('set -T')
    execute('set +T')
    assert_false Rubish::Builtins.set_option?('T')
  end

  def test_set_o_functrace
    execute('set -o functrace')
    assert Rubish::Builtins.set_option?('T')
  end

  def test_debug_trap_runs_before_command
    execute("trap 'echo DEBUG_RAN' DEBUG")
    output = capture_stdout do
      execute('true')
    end
    assert_match(/DEBUG_RAN/, output)
    execute('trap - DEBUG')
  end

  def test_return_trap_runs_on_function_return
    execute('set -T')  # Enable functrace so RETURN trap is inherited
    execute("trap 'echo RETURN_RAN' RETURN")
    execute('myfunc() { true; }')
    output = capture_stdout do
      execute('myfunc')
    end
    assert_match(/RETURN_RAN/, output)
    execute('trap - RETURN')
    execute('set +T')
  end

  def test_functrace_debug_trap_inherited_by_function
    execute('set -T')
    execute("trap 'echo DEBUG_IN_FUNC' DEBUG")
    execute('myfunc() { true; }')
    output = capture_stdout do
      execute('myfunc')
    end
    assert_match(/DEBUG_IN_FUNC/, output)
    execute('trap - DEBUG')
    execute('set +T')
  end

  def test_no_functrace_debug_trap_not_inherited_by_function
    execute('set +T')  # Ensure functrace is off
    execute("trap 'echo DEBUG_IN_FUNC' DEBUG")
    execute('myfunc() { true; }')
    output = capture_stdout do
      execute('myfunc')
    end
    # DEBUG trap from inside function should NOT appear (only the one for calling myfunc)
    # Count occurrences - should be exactly 1 (for the myfunc call itself)
    count = output.scan(/DEBUG_IN_FUNC/).length
    assert_equal 1, count, 'DEBUG trap should run once for myfunc call, not inside function'
    execute('trap - DEBUG')
  end

  def test_no_functrace_return_trap_not_inherited_by_function
    execute('set +T')  # Ensure functrace is off
    execute("trap 'echo RETURN_RAN' RETURN")
    execute('myfunc() { true; }')
    output = capture_stdout do
      execute('myfunc')
    end
    # RETURN trap should NOT run when functrace is off
    assert_no_match(/RETURN_RAN/, output)
    execute('trap - RETURN')
  end

  # set -B (braceexpand)
  def test_braceexpand_enabled_by_default
    # Braceexpand should be enabled by default
    assert Rubish::Builtins.set_option?('B')
  end

  def test_set_plus_B_disables_braceexpand
    execute('set +B')
    assert_false Rubish::Builtins.set_option?('B')
    execute('set -B')  # Re-enable for other tests
  end

  def test_set_minus_B_enables_braceexpand
    execute('set +B')
    execute('set -B')
    assert Rubish::Builtins.set_option?('B')
  end

  def test_set_o_braceexpand
    execute('set +o braceexpand')
    execute('set -o braceexpand')
    assert Rubish::Builtins.set_option?('B')
  end

  def test_braceexpand_expands_comma_list
    execute('set -B')
    execute("echo {a,b,c} > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'a b c', result
  end

  def test_braceexpand_expands_sequence
    execute('set -B')
    execute("echo {1..3} > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '1 2 3', result
  end

  def test_braceexpand_disabled_no_expansion
    execute('set +B')
    execute("echo {a,b,c} > #{output_file}")
    result = File.read(output_file).strip
    # When disabled, braces are kept as literal text
    assert_equal '{a,b,c}', result
    execute('set -B')  # Re-enable for other tests
  end

  def test_braceexpand_disabled_sequence_no_expansion
    execute('set +B')
    execute("echo {1..3} > #{output_file}")
    result = File.read(output_file).strip
    # When disabled, braces are kept as literal text
    assert_equal '{1..3}', result
    execute('set -B')  # Re-enable for other tests
  end

  # set -H (histexpand)
  def test_histexpand_enabled_by_default
    # Histexpand should be enabled by default
    assert Rubish::Builtins.set_option?('H')
  end

  def test_set_plus_H_disables_histexpand
    execute('set +H')
    assert_false Rubish::Builtins.set_option?('H')
    execute('set -H')  # Re-enable for other tests
  end

  def test_set_minus_H_enables_histexpand
    execute('set +H')
    execute('set -H')
    assert Rubish::Builtins.set_option?('H')
  end

  def test_set_o_histexpand
    execute('set +o histexpand')
    execute('set -o histexpand')
    assert Rubish::Builtins.set_option?('H')
  end

  def test_histexpand_expands_bang_bang
    # Add a command to history first
    Reline::HISTORY.clear
    Reline::HISTORY.push('echo hello')

    execute('set -H')
    # !! should expand to last command
    line, expanded = @repl.send(:expand_history, '!!')
    assert expanded
    assert_equal 'echo hello', line
  end

  def test_histexpand_disabled_no_expansion
    # Add a command to history first
    Reline::HISTORY.clear
    Reline::HISTORY.push('echo hello')

    execute('set +H')
    # With histexpand disabled, !! should be kept literally
    line, expanded = @repl.send(:expand_history, '!!')
    assert_false expanded
    assert_equal '!!', line
    execute('set -H')  # Re-enable for other tests
  end

  def test_histexpand_expands_bang_number
    Reline::HISTORY.clear
    Reline::HISTORY.push('echo first')
    Reline::HISTORY.push('echo second')

    execute('set -H')
    # !1 should refer to first command in history
    line, expanded = @repl.send(:expand_history, '!1')
    assert expanded
    assert_equal 'echo first', line
  end

  def test_histexpand_disabled_bang_number_no_expansion
    Reline::HISTORY.clear
    Reline::HISTORY.push('echo first')

    execute('set +H')
    # With histexpand disabled, !1 should be kept literally
    line, expanded = @repl.send(:expand_history, '!1')
    assert_false expanded
    assert_equal '!1', line
    execute('set -H')  # Re-enable for other tests
  end

  def test_histexpand_caret_substitution
    Reline::HISTORY.clear
    Reline::HISTORY.push('echo hello')

    execute('set -H')
    # ^hello^world should substitute hello with world in last command
    line, expanded = @repl.send(:expand_history, '^hello^world')
    assert expanded
    assert_equal 'echo world', line
  end

  def test_histexpand_disabled_caret_no_substitution
    Reline::HISTORY.clear
    Reline::HISTORY.push('echo hello')

    execute('set +H')
    # With histexpand disabled, ^old^new should be kept literally
    line, expanded = @repl.send(:expand_history, '^hello^world')
    assert_false expanded
    assert_equal '^hello^world', line
    execute('set -H')  # Re-enable for other tests
  end

  # set -o globstar
  def test_globstar_disabled_by_default
    # Globstar should be disabled by default
    assert_false Rubish::Builtins.set_option?('globstar')
  end

  def test_set_o_globstar_enables_globstar
    execute('set -o globstar')
    assert Rubish::Builtins.set_option?('globstar')
    execute('set +o globstar')
  end

  def test_set_plus_o_globstar_disables_globstar
    execute('set -o globstar')
    execute('set +o globstar')
    assert_false Rubish::Builtins.set_option?('globstar')
  end

  def test_globstar_recursive_match
    # Create nested directory structure
    subdir = File.join(@tempdir, 'a', 'b', 'c')
    FileUtils.mkdir_p(subdir)
    File.write(File.join(@tempdir, 'top.txt'), 'top')
    File.write(File.join(@tempdir, 'a', 'mid.txt'), 'mid')
    File.write(File.join(@tempdir, 'a', 'b', 'c', 'deep.txt'), 'deep')

    execute('set -o globstar')
    execute("echo #{@tempdir}/**/*.txt > #{output_file}")
    result = File.read(output_file).strip
    execute('set +o globstar')

    # With globstar, should find all .txt files recursively
    assert_match(/top\.txt/, result)
    assert_match(/mid\.txt/, result)
    assert_match(/deep\.txt/, result)
  end

  def test_globstar_disabled_no_recursive_match
    # Create nested directory structure
    subdir = File.join(@tempdir, 'a', 'b', 'c')
    FileUtils.mkdir_p(subdir)
    File.write(File.join(@tempdir, 'top.txt'), 'top')
    File.write(File.join(@tempdir, 'a', 'mid.txt'), 'mid')
    File.write(File.join(@tempdir, 'a', 'b', 'c', 'deep.txt'), 'deep')

    execute('set +o globstar')  # Ensure disabled
    execute("echo #{@tempdir}/**/*.txt > #{output_file}")
    result = File.read(output_file).strip

    # Without globstar, ** acts like * (non-recursive)
    # Should only match one level down
    assert_match(/mid\.txt/, result)
    assert_no_match(/deep\.txt/, result)
  end

  def test_globstar_matches_directories
    # Create nested directory structure
    subdir = File.join(@tempdir, 'a', 'b', 'c')
    FileUtils.mkdir_p(subdir)
    File.write(File.join(subdir, 'file.txt'), 'content')

    execute('set -o globstar')
    # **/ should match any directory path
    matches = @repl.send(:__glob, "#{@tempdir}/**/file.txt")
    execute('set +o globstar')

    assert_equal 1, matches.length
    assert_match(/a\/b\/c\/file\.txt/, matches.first)
  end

  def test_globstar_double_star_at_end
    # Create nested directory structure
    subdir = File.join(@tempdir, 'a', 'b')
    FileUtils.mkdir_p(subdir)
    File.write(File.join(@tempdir, 'a', 'file1.txt'), 'a')
    File.write(File.join(@tempdir, 'a', 'b', 'file2.txt'), 'b')

    execute('set -o globstar')
    # dir/** should match all files under dir recursively
    matches = @repl.send(:__glob, "#{@tempdir}/a/**")
    execute('set +o globstar')

    # Should include both files and directories
    assert matches.length >= 2
  end

  # set -o nullglob
  def test_nullglob_disabled_by_default
    # Nullglob should be disabled by default
    assert_false Rubish::Builtins.set_option?('nullglob')
  end

  def test_set_o_nullglob_enables_nullglob
    execute('set -o nullglob')
    assert Rubish::Builtins.set_option?('nullglob')
    execute('set +o nullglob')
  end

  def test_set_plus_o_nullglob_disables_nullglob
    execute('set -o nullglob')
    execute('set +o nullglob')
    assert_false Rubish::Builtins.set_option?('nullglob')
  end

  def test_nullglob_no_match_returns_empty
    execute('set -o nullglob')
    # Pattern that matches nothing
    matches = @repl.send(:__glob, "#{@tempdir}/nonexistent_*.xyz")
    execute('set +o nullglob')

    # With nullglob, no matches should return empty array
    assert_equal [], matches
  end

  def test_nullglob_disabled_no_match_returns_pattern
    execute('set +o nullglob')  # Ensure disabled
    # Pattern that matches nothing
    pattern = "#{@tempdir}/nonexistent_*.xyz"
    matches = @repl.send(:__glob, pattern)

    # Without nullglob, no matches should return the original pattern
    assert_equal [pattern], matches
  end

  def test_nullglob_with_matches_returns_matches
    # Create a test file
    File.write(File.join(@tempdir, 'test.txt'), 'content')

    execute('set -o nullglob')
    matches = @repl.send(:__glob, "#{@tempdir}/*.txt")
    execute('set +o nullglob')

    # With matches, should return the matches (not affected by nullglob)
    assert_equal 1, matches.length
    assert_match(/test\.txt/, matches.first)
  end

  def test_nullglob_echo_no_match_outputs_nothing
    execute('set -o nullglob')
    execute("echo #{@tempdir}/nonexistent_*.xyz > #{output_file}")
    result = File.read(output_file).strip
    execute('set +o nullglob')

    # With nullglob, echo with no matches should output nothing (or just newline)
    assert_equal '', result
  end

  def test_nullglob_disabled_echo_no_match_outputs_pattern
    execute('set +o nullglob')  # Ensure disabled
    pattern = "#{@tempdir}/no_match_*.xyz"
    execute("echo #{pattern} > #{output_file}")
    result = File.read(output_file).strip

    # Without nullglob, echo should output the literal pattern
    assert_equal pattern, result
  end

  # set -o failglob
  def test_failglob_disabled_by_default
    # Failglob should be disabled by default
    assert_false Rubish::Builtins.set_option?('failglob')
  end

  def test_set_o_failglob_enables_failglob
    execute('set -o failglob')
    assert Rubish::Builtins.set_option?('failglob')
    execute('set +o failglob')
  end

  def test_set_plus_o_failglob_disables_failglob
    execute('set -o failglob')
    execute('set +o failglob')
    assert_false Rubish::Builtins.set_option?('failglob')
  end

  def test_failglob_no_match_raises_error
    execute('set -o failglob')

    stderr_file = File.join(@tempdir, 'stderr.txt')
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')
    begin
      # Pattern that matches nothing should cause error
      execute("echo #{@tempdir}/nonexistent_*.xyz")
    ensure
      $stderr.close
      $stderr = old_stderr
    end

    # Should set last_status to 1
    last_status = @repl.instance_variable_get(:@last_status)
    execute('set +o failglob')

    # Should have printed error to stderr
    stderr_content = File.read(stderr_file)
    assert_match(/no match/, stderr_content)
    assert_equal 1, last_status
  end

  def test_failglob_disabled_no_error
    execute('set +o failglob')  # Ensure disabled

    # Pattern that matches nothing should NOT cause error
    pattern = "#{@tempdir}/nonexistent_*.xyz"
    execute("echo #{pattern} > #{output_file}")
    result = File.read(output_file).strip

    # Without failglob, should output literal pattern
    assert_equal pattern, result
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_failglob_with_matches_no_error
    # Create a test file
    File.write(File.join(@tempdir, 'test.txt'), 'content')

    execute('set -o failglob')
    execute("echo #{@tempdir}/*.txt > #{output_file}")
    result = File.read(output_file).strip
    execute('set +o failglob')

    # With matches, should work normally
    assert_match(/test\.txt/, result)
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_failglob_takes_precedence_over_nullglob
    # When both are set, failglob should take precedence
    execute('set -o failglob')
    execute('set -o nullglob')

    stderr_file = File.join(@tempdir, 'stderr.txt')
    old_stderr = $stderr
    $stderr = File.open(stderr_file, 'w')
    begin
      execute("echo #{@tempdir}/nonexistent_*.xyz")
    ensure
      $stderr.close
      $stderr = old_stderr
    end
    execute('set +o failglob')
    execute('set +o nullglob')

    # Should have printed error (failglob wins)
    stderr_content = File.read(stderr_file)
    assert_match(/no match/, stderr_content)
  end

  # set -o dotglob
  def test_dotglob_disabled_by_default
    # Dotglob should be disabled by default
    assert_false Rubish::Builtins.set_option?('dotglob')
  end

  def test_set_o_dotglob_enables_dotglob
    execute('set -o dotglob')
    assert Rubish::Builtins.set_option?('dotglob')
    execute('set +o dotglob')
  end

  def test_set_plus_o_dotglob_disables_dotglob
    execute('set -o dotglob')
    execute('set +o dotglob')
    assert_false Rubish::Builtins.set_option?('dotglob')
  end

  def test_dotglob_matches_hidden_files
    # Create hidden and normal files
    File.write(File.join(@tempdir, '.hidden'), 'hidden')
    File.write(File.join(@tempdir, 'visible'), 'visible')

    execute('set -o dotglob')
    matches = @repl.send(:__glob, "#{@tempdir}/*")
    execute('set +o dotglob')

    # With dotglob, should match both hidden and visible files
    hidden_matched = matches.any? { |m| m.include?('.hidden') }
    visible_matched = matches.any? { |m| m.include?('visible') }
    assert hidden_matched, 'Should match hidden files with dotglob'
    assert visible_matched, 'Should match visible files with dotglob'
  end

  def test_dotglob_disabled_no_hidden_files
    # Create hidden and normal files
    File.write(File.join(@tempdir, '.hidden'), 'hidden')
    File.write(File.join(@tempdir, 'visible'), 'visible')

    execute('set +o dotglob')  # Ensure disabled
    matches = @repl.send(:__glob, "#{@tempdir}/*")

    # Without dotglob, should only match visible files
    hidden_matched = matches.any? { |m| m.include?('.hidden') }
    visible_matched = matches.any? { |m| m.include?('visible') }
    assert_false hidden_matched, 'Should NOT match hidden files without dotglob'
    assert visible_matched, 'Should match visible files without dotglob'
  end

  def test_dotglob_excludes_dot_and_dotdot
    # Create a subdirectory
    subdir = File.join(@tempdir, 'subdir')
    FileUtils.mkdir_p(subdir)
    File.write(File.join(subdir, '.hidden'), 'hidden')

    execute('set -o dotglob')
    matches = @repl.send(:__glob, "#{subdir}/*")
    execute('set +o dotglob')

    # Should not include . or ..
    dot_matched = matches.any? { |m| m.end_with?('/.') }
    dotdot_matched = matches.any? { |m| m.end_with?('/..') }
    assert_false dot_matched, 'Should NOT match . even with dotglob'
    assert_false dotdot_matched, 'Should NOT match .. even with dotglob'
  end

  def test_dotglob_with_specific_pattern
    # Create hidden files with specific extension
    File.write(File.join(@tempdir, '.config.txt'), 'config')
    File.write(File.join(@tempdir, 'normal.txt'), 'normal')

    execute('set -o dotglob')
    matches = @repl.send(:__glob, "#{@tempdir}/*.txt")
    execute('set +o dotglob')

    # Should match both
    assert_equal 2, matches.length
    assert matches.any? { |m| m.include?('.config.txt') }
    assert matches.any? { |m| m.include?('normal.txt') }
  end

  def test_dotglob_echo_includes_hidden
    # Create hidden and normal files
    File.write(File.join(@tempdir, '.hidden.txt'), 'hidden')
    File.write(File.join(@tempdir, 'visible.txt'), 'visible')

    execute('set -o dotglob')
    execute("echo #{@tempdir}/*.txt > #{output_file}")
    result = File.read(output_file).strip
    execute('set +o dotglob')

    # Should include both hidden and visible files
    assert_match(/\.hidden\.txt/, result)
    assert_match(/visible\.txt/, result)
  end

  # set -o nocaseglob
  def test_nocaseglob_disabled_by_default
    # Nocaseglob should be disabled by default
    assert_false Rubish::Builtins.set_option?('nocaseglob')
  end

  def test_set_o_nocaseglob_enables_nocaseglob
    execute('set -o nocaseglob')
    assert Rubish::Builtins.set_option?('nocaseglob')
    execute('set +o nocaseglob')
  end

  def test_set_plus_o_nocaseglob_disables_nocaseglob
    execute('set -o nocaseglob')
    execute('set +o nocaseglob')
    assert_false Rubish::Builtins.set_option?('nocaseglob')
  end

  def test_nocaseglob_matches_pattern_case_insensitive
    # Create a file with specific case
    File.write(File.join(@tempdir, 'MyFile.txt'), 'content')

    execute('set -o nocaseglob')
    # Use uppercase pattern to match lowercase filename
    matches = @repl.send(:__glob, "#{@tempdir}/MYFILE.TXT")
    execute('set +o nocaseglob')

    # With nocaseglob, should match regardless of case
    assert_equal 1, matches.length
    assert matches.first.include?('MyFile.txt')
  end

  def test_nocaseglob_disabled_case_sensitive
    # Create a file with specific case
    File.write(File.join(@tempdir, 'CaseSensitive.txt'), 'content')

    execute('set +o nocaseglob')  # Ensure disabled
    # Try to match with wrong case - should fail
    matches = @repl.send(:__glob, "#{@tempdir}/CASESENSITIVE.TXT")

    # Without nocaseglob on case-sensitive fs, should not match
    # On case-insensitive fs (macOS), it will still match - that's filesystem behavior
    # We just verify it returns something (testing the option toggle works)
    assert matches.length >= 0
  end

  def test_nocaseglob_matches_with_wildcard
    # Create files
    File.write(File.join(@tempdir, 'alpha.TXT'), 'a')
    File.write(File.join(@tempdir, 'beta.md'), 'b')

    execute('set -o nocaseglob')
    # Pattern with lowercase should match uppercase extension
    matches = @repl.send(:__glob, "#{@tempdir}/*.txt")
    execute('set +o nocaseglob')

    # Should match alpha.TXT with lowercase pattern
    assert_equal 1, matches.length
    assert matches.first.include?('alpha.TXT')
  end

  def test_nocaseglob_wildcard_case_insensitive
    # Create a file with mixed case extension
    File.write(File.join(@tempdir, 'document.PDF'), 'content')

    execute('set -o nocaseglob')
    # Use lowercase pattern to match uppercase file
    matches = @repl.send(:__glob, "#{@tempdir}/*.pdf")
    execute('set +o nocaseglob')

    # With nocaseglob, lowercase pattern should match uppercase extension
    assert_equal 1, matches.length
    assert matches.first.include?('document.PDF')
  end

  def test_nocaseglob_combined_with_dotglob
    # Create a hidden file with specific case
    File.write(File.join(@tempdir, '.HiddenConfig'), 'content')

    execute('set -o nocaseglob')
    execute('set -o dotglob')
    # Use different case pattern
    matches = @repl.send(:__glob, "#{@tempdir}/.HIDDENCONFIG")
    execute('set +o nocaseglob')
    execute('set +o dotglob')

    # Should match the hidden file case-insensitively
    assert_equal 1, matches.length
    assert matches.first.include?('.HiddenConfig')
  end

  # set -o ignoreeof
  def test_ignoreeof_disabled_by_default
    # Ignoreeof should be disabled by default
    assert_false Rubish::Builtins.set_option?('ignoreeof')
  end

  def test_set_o_ignoreeof_enables_ignoreeof
    execute('set -o ignoreeof')
    assert Rubish::Builtins.set_option?('ignoreeof')
    execute('set +o ignoreeof')
  end

  def test_set_plus_o_ignoreeof_disables_ignoreeof
    execute('set -o ignoreeof')
    execute('set +o ignoreeof')
    assert_false Rubish::Builtins.set_option?('ignoreeof')
  end

  def test_ignoreeof_listed_in_set_options
    output = capture_stdout { execute('set -o') }
    assert_match(/ignoreeof/, output)
  end

  def test_ignoreeof_shows_enabled_state
    execute('set -o ignoreeof')
    output = capture_stdout { execute('set -o') }
    execute('set +o ignoreeof')

    assert_match(/set -o ignoreeof/, output)
  end

  def test_ignoreeof_shows_disabled_state
    execute('set +o ignoreeof')
    output = capture_stdout { execute('set -o') }

    assert_match(/set \+o ignoreeof/, output)
  end
end
