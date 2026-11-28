# frozen_string_literal: true

require_relative 'test_helper'

# An Interrupt raised while the shell waits for a command (a Ctrl-C in a
# program embedding the REPL, which runs rubish without its own INT trap)
# must not abandon the children: the same SIGINT went to them, and
# nothing else would collect their end
class TestInterruptedCommand < Test::Unit::TestCase
  def children_named(name)
    IO.popen(['ps', '-axo', 'pid=,ppid=,stat=,comm='], &:read).lines.map do |line|
      pid, ppid, stat, comm = line.split
      [pid.to_i, stat] if ppid.to_i == Process.pid && File.basename(comm) == name
    end.compact
  end

  def wait_for_child(name)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      found = children_named(name).find { |_, stat| !stat.start_with?('Z') }
      return found.first if found
      flunk "no #{name} child appeared" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.02
    end
  end

  # Runs the command on a thread, raises Interrupt into its wait, then sends
  # the children the SIGINT a terminal's Ctrl-C would have; answers their pids
  def interrupt_while_waiting(runnable, *child_names)
    runner = Thread.new { runnable.run }
    runner.report_on_exception = false
    pids = child_names.map { |name| wait_for_child(name) }
    runner.raise(Interrupt)
    sleep 0.1
    pids.each { |pid| Process.kill('INT', pid) }
    assert_raise(Interrupt) { runner.join }
    pids
  end

  def assert_collected(pids)
    sleep 0.2
    pids.each do |pid|
      assert_raise(Errno::ECHILD, "child #{pid} should have been waited for") { Process.waitpid(pid, Process::WNOHANG) }
    end
  end

  def test_an_interrupt_during_the_wait_still_collects_the_command
    assert_collected interrupt_while_waiting(Rubish::Command.new('sleep', '5'), 'sleep')
  end

  def test_an_interrupt_during_the_wait_still_collects_every_member_of_a_pipeline
    pipeline = Rubish::Pipeline.new(Rubish::Command.new('sleep', '5'), Rubish::Command.new('cat'))
    assert_collected interrupt_while_waiting(pipeline, 'sleep', 'cat')
  end
end
