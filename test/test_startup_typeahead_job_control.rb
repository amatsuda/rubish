# frozen_string_literal: true

require_relative 'test_helper'
require 'pty'
require 'shellwords'
require 'timeout'
require 'tmpdir'

# A shell started by a parent that does not make it a process-group leader
# (login(1) under Ghostty, or `sh -c 'rubish; true'`) moves itself into its
# own group and then takes the terminal. Anything typed in between must not
# be read from the background group, or the kernel stops the whole shell
# with SIGTTIN before the first prompt, and Ctrl-C cannot reach it.
class TestStartupTypeaheadJobControl < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)
  LIB = File.expand_path('../lib', __dir__)

  # Outside Bundler, as from a login shell, loading fiddle for tcsetpgrp
  # resolves through RubyGems and leaves a window wide enough to hit
  def spawn_outside_bundler(env, cmd, &block)
    if defined?(Bundler)
      Bundler.with_unbundled_env { PTY.spawn(env, '/bin/sh', '-c', cmd, &block) }
    else
      PTY.spawn(env, '/bin/sh', '-c', cmd, &block)
    end
  end

  def test_typing_during_startup_as_a_non_leader_does_not_stop_the_shell
    Dir.mktmpdir('rubish_pty') do |home|
      env = {'HOME' => home, 'TERM' => 'xterm', 'LANG' => 'en_US.UTF-8'}
      # The trailing `true` keeps sh from exec'ing, so rubish is forked
      # into sh's process group instead of leading one
      argv = [RbConfig.ruby, '-I', LIB]
      # The child runs without Bundler, where Ruby's own reline may be
      # missing (2.6) or too old for setup_reline (3.0 ships 0.2); hand it
      # the bundled copy
      if (reline = Gem.loaded_specs['reline'])
        argv += ['-I', File.join(reline.full_gem_path, 'lib')]
      end
      cmd = "#{(argv + [EXE, '--norc']).shelljoin}; true"
      spawn_outside_bundler(env, cmd) do |reader, writer, pid|
        output = +''
        drainer = Thread.new { loop { output << reader.readpartial(4096) } rescue nil }
        begin
          deadline = Time.now + 1.5
          while Time.now < deadline
            writer.write('a')
            sleep 0.005
          end
          writer.write("\x15echo MARK_$((40+2))\r")
          Timeout.timeout(10) { sleep 0.05 until output.include?('MARK_42') } rescue nil
          shell = `pgrep -P #{pid}`.split.first
          state = shell && `ps -o stat= -p #{shell}`.strip
          assert_include output, 'MARK_42', "the shell never ran the command (process state: #{state.inspect})"
        ensure
          `pgrep -P #{pid}`.split.each { |child| Process.kill('KILL', child.to_i) rescue nil }
          Process.kill('KILL', pid) rescue nil
          Timeout.timeout(5) { drainer.join } rescue nil
          Process.wait(pid) rescue nil
        end
      end
    end
  end
end
