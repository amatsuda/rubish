# frozen_string_literal: true

require_relative 'test_helper'

# An Interrupt raised while the shell waits for a command (a Ctrl-C in a
# program embedding the REPL, which runs rubish without its own INT trap)
# must not abandon the child: the same SIGINT went to the child, and
# nothing else would collect its end
class TestInterruptedCommand < Test::Unit::TestCase
  def children_named(name)
    IO.popen(['ps', '-axo', 'pid=,ppid=,stat=,comm='], &:read).lines.filter_map do |line|
      pid, ppid, stat, comm = line.split
      [pid.to_i, stat] if ppid.to_i == Process.pid && File.basename(comm) == name
    end
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

  def interrupt_while_waiting(runnable, child_name)
    runner = Thread.new { runnable.run }
    runner.report_on_exception = false
    pid = wait_for_child(child_name)
    runner.raise(Interrupt)
    sleep 0.1
    Process.kill('INT', pid)
    assert_raise(Interrupt) { runner.join }
    pid
  end

  def assert_collected(pid)
    sleep 0.2
    zombies = children_named('sleep').select { |p, stat| p == pid && stat.start_with?('Z') }
    assert_empty zombies, 'the interrupted child was left a zombie'
    assert_raise(Errno::ECHILD, 'the child should have been waited for') { Process.waitpid(pid, Process::WNOHANG) }
  end

  def test_an_interrupt_during_the_wait_still_collects_the_command
    pid = interrupt_while_waiting(Rubish::Command.new('sleep', '5'), 'sleep')
    assert_collected(pid)
  end

  def test_an_interrupt_during_the_wait_still_collects_a_pipeline
    pipeline = Rubish::Pipeline.new(Rubish::Command.new('sleep', '5'), Rubish::Command.new('cat'))
    pid = interrupt_while_waiting(pipeline, 'sleep')
    assert_collected(pid)
  end
end
