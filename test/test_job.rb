# frozen_string_literal: true

require_relative 'test_helper'

class TestJob < Test::Unit::TestCase
  def setup
    Rubish::JobManager.instance.clear
  end

  def teardown
    Rubish::JobManager.instance.clear
  end

  def test_job_creation
    job = Rubish::Job.new(id: 1, pid: 12345, pgid: 12345, command: 'sleep 10')
    assert_equal 1, job.id
    assert_equal 12345, job.pid
    assert_equal 12345, job.pgid
    assert_equal 'sleep 10', job.command
    assert_equal :running, job.status
  end

  def test_job_status_strings
    job = Rubish::Job.new(id: 1, pid: 12345, pgid: 12345, command: 'sleep 10')

    job.status = :running
    assert_equal 'Running', job.status_string

    job.status = :stopped
    assert_equal 'Stopped', job.status_string

    job.status = :done
    assert_equal 'Done', job.status_string
  end

  def test_job_predicates
    job = Rubish::Job.new(id: 1, pid: 12345, pgid: 12345, command: 'sleep 10')

    job.status = :running
    assert job.running?
    assert !job.stopped?
    assert !job.done?

    job.status = :stopped
    assert !job.running?
    assert job.stopped?
    assert !job.done?

    job.status = :done
    assert !job.running?
    assert !job.stopped?
    assert job.done?
  end

  def test_job_to_s
    job = Rubish::Job.new(id: 1, pid: 12345, pgid: 12345, command: 'sleep 10')
    assert_match(/\[1\]/, job.to_s)
    assert_match(/Running/, job.to_s)
    assert_match(/sleep 10/, job.to_s)
  end

  def test_job_manager_add
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 12345, pgid: 12345, command: 'sleep 10')

    assert_equal 1, job.id
    assert_equal 12345, job.pid
  end

  def test_job_manager_get
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 12345, pgid: 12345, command: 'sleep 10')

    found = manager.get(job.id)
    assert_equal job, found

    not_found = manager.get(999)
    assert_nil not_found
  end

  def test_job_manager_remove
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 12345, pgid: 12345, command: 'sleep 10')

    manager.remove(job.id)
    assert_nil manager.get(job.id)
  end

  def test_job_manager_all
    manager = Rubish::JobManager.instance
    job1 = manager.add(pid: 111, pgid: 111, command: 'cmd1')
    job2 = manager.add(pid: 222, pgid: 222, command: 'cmd2')

    all = manager.all
    assert_equal 2, all.length
    assert_includes all, job1
    assert_includes all, job2
  end

  def test_job_manager_active
    manager = Rubish::JobManager.instance
    job1 = manager.add(pid: 111, pgid: 111, command: 'cmd1')
    job2 = manager.add(pid: 222, pgid: 222, command: 'cmd2')
    job2.status = :done

    active = manager.active
    assert_equal 1, active.length
    assert_includes active, job1
    assert !active.include?(job2)
  end

  def test_job_manager_find_by_pid
    manager = Rubish::JobManager.instance
    job = manager.add(pid: 12345, pgid: 12345, command: 'sleep 10')

    found = manager.find_by_pid(12345)
    assert_equal job, found

    not_found = manager.find_by_pid(99999)
    assert_nil not_found
  end

  def test_job_manager_last
    manager = Rubish::JobManager.instance

    assert_nil manager.last

    job1 = manager.add(pid: 111, pgid: 111, command: 'cmd1')
    assert_equal job1, manager.last

    job2 = manager.add(pid: 222, pgid: 222, command: 'cmd2')
    assert_equal job2, manager.last
  end

  def test_job_manager_increments_id
    manager = Rubish::JobManager.instance
    job1 = manager.add(pid: 111, pgid: 111, command: 'cmd1')
    job2 = manager.add(pid: 222, pgid: 222, command: 'cmd2')

    assert_equal 1, job1.id
    assert_equal 2, job2.id
  end
end
