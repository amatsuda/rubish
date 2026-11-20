# frozen_string_literal: true

require_relative 'test_helper'

# Builtins that must run in the shell process (cd, export, command, set, ...)
# still have to honour redirections on their output.
class TestProcessBuiltinRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_process_builtin_redirect')
    @original_dir = Dir.pwd
    @original_env = ENV.to_h.dup
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def out_file
    File.join(@tempdir, 'out.txt')
  end

  def test_export_listing_goes_to_redirect_target
    execute('export RUBISH_PBR_X=1')
    stdout = capture_stdout { execute("export > #{out_file}") }
    assert_equal '', stdout
    assert_match(/RUBISH_PBR_X/, File.read(out_file))
  end

  def test_command_v_output_can_be_discarded
    stdout = capture_stdout { execute('command -v cd > /dev/null') }
    assert_equal '', stdout
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_cd_error_can_be_silenced
    output = capture_output { execute('cd /nonexistent_rubish_dir 2> /dev/null') }
    assert_equal '', output
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_cd_error_goes_to_stderr_redirect_target
    err_file = File.join(@tempdir, 'err.txt')
    capture_output { execute("cd /nonexistent_rubish_dir 2> #{err_file}") }
    assert_match(/No such file or directory/, File.read(err_file))
  end

  def test_declare_p_listing_goes_to_redirect_target
    execute('RUBISH_PBR_Y=2')
    stdout = capture_stdout { execute("declare -p RUBISH_PBR_Y > #{out_file}") }
    assert_equal '', stdout
    assert_match(/RUBISH_PBR_Y/, File.read(out_file))
  end

  def test_cd_still_changes_directory_with_redirect
    execute("cd #{@tempdir} > /dev/null")
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_redirect_does_not_leak_into_following_command
    out = capture_stdout { execute("export > #{out_file}; echo visible") }
    assert_equal "visible\n", out
  end
end
