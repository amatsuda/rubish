# frozen_string_literal: true

require_relative 'test_helper'

class TestWait < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_wait_test')
    Rubish::JobManager.instance.clear
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::JobManager.instance.clear
  end

  # Test wait is a builtin
  def test_wait_is_builtin
    assert Rubish::Builtins.builtin?('wait')
  end

  # Test wait with no jobs returns true
  def test_wait_no_jobs
    result = Rubish::Builtins.run('wait', [])
    assert result
  end

  # Test wait for invalid job spec
  def test_wait_invalid_job_spec
    output = capture_output do
      result = Rubish::Builtins.run('wait', ['%999'])
      assert_false result
    end
    assert_match(/no such job/, output)
  end

  # Test wait for invalid pid
  def test_wait_invalid_pid
    output = capture_output do
      result = Rubish::Builtins.run('wait', ['999999'])
      assert_false result
    end
    assert_match(/not a child/, output)
  end

  # Test type identifies wait as builtin
  def test_type_identifies_wait_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['wait']) }
    assert_match(/wait is a shell builtin/, output)
  end

  # Test wait with background job
  def test_wait_for_background_job
    # Start a background job
    output_file = File.join(@tempdir, 'output.txt')
    execute("sleep 0.1 && echo done > #{output_file} &")

    # Wait should block until done
    execute('wait')

    # File should exist after wait
    assert File.exist?(output_file), 'Output file should exist after wait'
    assert_equal "done\n", File.read(output_file)
  end

  # Test wait returns success for successful job
  def test_wait_returns_success_for_successful_job
    execute('true &')
    result = Rubish::Builtins.run('wait', [])
    assert result
  end
end
