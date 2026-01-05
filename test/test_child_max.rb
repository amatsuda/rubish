# frozen_string_literal: true

require_relative 'test_helper'

class TestCHILD_MAX < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_child_max_test')
    Dir.chdir(@tempdir)

    # Clear any existing jobs
    Rubish::JobManager.instance.clear
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }

    # Clear jobs
    Rubish::JobManager.instance.clear
  end

  # Basic CHILD_MAX functionality

  def test_child_max_limit_returns_nil_when_not_set
    ENV.delete('CHILD_MAX')
    assert_nil Rubish::JobManager.instance.child_max_limit
  end

  def test_child_max_limit_returns_nil_for_empty_value
    ENV['CHILD_MAX'] = ''
    assert_nil Rubish::JobManager.instance.child_max_limit
  end

  def test_child_max_limit_returns_nil_for_zero
    ENV['CHILD_MAX'] = '0'
    assert_nil Rubish::JobManager.instance.child_max_limit
  end

  def test_child_max_limit_returns_nil_for_negative
    ENV['CHILD_MAX'] = '-5'
    assert_nil Rubish::JobManager.instance.child_max_limit
  end

  def test_child_max_limit_returns_value_for_positive
    ENV['CHILD_MAX'] = '10'
    assert_equal 10, Rubish::JobManager.instance.child_max_limit
  end

  def test_child_max_limit_parses_integer
    ENV['CHILD_MAX'] = '5'
    assert_equal 5, Rubish::JobManager.instance.child_max_limit
  end

  # Active count tracking

  def test_active_count_is_zero_initially
    assert_equal 0, Rubish::JobManager.instance.active_count
  end

  def test_active_count_includes_running_jobs
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 99999, pgid: 99999, command: 'test')
    job.status = :running

    assert_equal 1, manager.active_count
  end

  def test_active_count_includes_stopped_jobs
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 99999, pgid: 99999, command: 'test')
    job.status = :stopped

    assert_equal 1, manager.active_count
  end

  def test_active_count_excludes_done_jobs
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 99999, pgid: 99999, command: 'test')
    job.status = :done

    assert_equal 0, manager.active_count
  end

  def test_active_count_multiple_jobs
    manager = Rubish::JobManager.instance
    job1 = manager.add(pid: 99991, pgid: 99991, command: 'test1')
    job2 = manager.add(pid: 99992, pgid: 99992, command: 'test2')
    job3 = manager.add(pid: 99993, pgid: 99993, command: 'test3')

    job1.status = :running
    job2.status = :stopped
    job3.status = :done

    assert_equal 2, manager.active_count
  end

  # wait_for_child_slot behavior

  def test_wait_for_child_slot_returns_true_when_no_limit
    ENV.delete('CHILD_MAX')
    assert_equal true, Rubish::JobManager.instance.wait_for_child_slot
  end

  def test_wait_for_child_slot_returns_true_when_below_limit
    ENV['CHILD_MAX'] = '5'
    manager = Rubish::JobManager.instance

    # Add 2 running jobs (below limit of 5)
    job1 = manager.add(pid: 99991, pgid: 99991, command: 'test1')
    job2 = manager.add(pid: 99992, pgid: 99992, command: 'test2')
    job1.status = :running
    job2.status = :running

    assert_equal true, manager.wait_for_child_slot
  end

  def test_wait_for_child_slot_returns_true_at_limit_minus_one
    ENV['CHILD_MAX'] = '3'
    manager = Rubish::JobManager.instance

    # Add 2 running jobs (at limit - 1 for limit of 3)
    job1 = manager.add(pid: 99991, pgid: 99991, command: 'test1')
    job2 = manager.add(pid: 99992, pgid: 99992, command: 'test2')
    job1.status = :running
    job2.status = :running

    assert_equal true, manager.wait_for_child_slot
  end

  # Integration test with real processes

  def test_child_max_with_real_background_jobs
    ENV['CHILD_MAX'] = '2'

    repl = Rubish::REPL.new
    # Enable monitor mode for job control
    Rubish::Builtins.run('set', ['-m'])

    # Start first background job
    repl.send(:execute, 'sleep 0.1 &')
    count1 = Rubish::JobManager.instance.active_count
    assert count1 <= 2, "Should have at most 2 active jobs, got #{count1}"

    # Start second background job
    repl.send(:execute, 'sleep 0.1 &')
    count2 = Rubish::JobManager.instance.active_count
    assert count2 <= 2, "Should have at most 2 active jobs, got #{count2}"

    # Wait for jobs to complete
    sleep 0.2
    Rubish::JobManager.instance.check_background_jobs

    # Disable monitor mode
    Rubish::Builtins.run('set', ['+m'])
  end
end
