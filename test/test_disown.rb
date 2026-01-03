# frozen_string_literal: true

require_relative 'test_helper'

class TestDisown < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_disown_test')
    Rubish::JobManager.instance.clear
  end

  def teardown
    Rubish::JobManager.instance.clear
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test disown is a builtin
  def test_disown_is_builtin
    assert Rubish::Builtins.builtin?('disown')
  end

  # Test disown with no jobs
  def test_disown_no_jobs
    output = capture_output do
      result = Rubish::Builtins.run('disown', [])
      assert_false result
    end
    assert_match(/no such job/, output)
  end

  # Test disown removes job from table
  def test_disown_removes_job
    manager = Rubish::JobManager.instance
    # Add a mock job
    job = manager.add(pid: 99999, pgid: 99999, command: 'sleep 100')
    job_id = job.id

    Rubish::Builtins.run('disown', ["%#{job_id}"])
    assert_nil manager.get(job_id)
  end

  # Test disown with -a removes all jobs
  def test_disown_a_removes_all
    manager = Rubish::JobManager.instance
    # Add mock jobs
    manager.add(pid: 99991, pgid: 99991, command: 'sleep 100')
    manager.add(pid: 99992, pgid: 99992, command: 'sleep 100')
    manager.add(pid: 99993, pgid: 99993, command: 'sleep 100')

    Rubish::Builtins.run('disown', ['-a'])
    assert manager.all.empty?
  end

  # Test disown with invalid option
  def test_disown_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('disown', ['-x'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test disown with nonexistent job
  def test_disown_nonexistent_job
    output = capture_output do
      result = Rubish::Builtins.run('disown', ['%999'])
      assert_false result
    end
    assert_match(/no such job/, output)
  end

  # Test disown removes current job without args
  def test_disown_current_job
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 99999, pgid: 99999, command: 'sleep 100')

    result = Rubish::Builtins.run('disown', [])
    assert result
    assert_nil manager.get(job.id)
  end

  # Test disown by PID
  def test_disown_by_pid
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 88888, pgid: 88888, command: 'sleep 100')

    result = Rubish::Builtins.run('disown', ['88888'])
    assert result
    assert_nil manager.get(job.id)
  end

  # Test disown -h marks job but keeps it
  def test_disown_h_marks_nohup
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 99999, pgid: 99999, command: 'sleep 100')
    job_id = job.id

    result = Rubish::Builtins.run('disown', ['-h', "%#{job_id}"])
    assert result
    # Job should still exist
    remaining_job = manager.get(job_id)
    assert_not_nil remaining_job
    assert_equal :nohup, remaining_job.status
  end

  # Test type identifies disown as builtin
  def test_type_identifies_disown_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['disown']) }
    assert_match(/disown is a shell builtin/, output)
  end

  # Test disown multiple jobs
  def test_disown_multiple_jobs
    manager = Rubish::JobManager.instance
    job1 = manager.add(pid: 99991, pgid: 99991, command: 'sleep 100')
    job2 = manager.add(pid: 99992, pgid: 99992, command: 'sleep 100')
    job3 = manager.add(pid: 99993, pgid: 99993, command: 'sleep 100')

    Rubish::Builtins.run('disown', ["%#{job1.id}", "%#{job2.id}"])

    assert_nil manager.get(job1.id)
    assert_nil manager.get(job2.id)
    assert_not_nil manager.get(job3.id)
  end

  # Test disown via REPL
  def test_disown_via_repl
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 99999, pgid: 99999, command: 'sleep 100')
    job_id = job.id

    execute("disown %#{job_id}")
    assert_nil manager.get(job_id)
  end
end
