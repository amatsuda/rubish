# frozen_string_literal: true

require_relative 'test_helper'

# Libraries that only one feature needs are loaded when that feature runs,
# not at startup
class TestLazyStdlibLoading < Test::Unit::TestCase
  LIB = File.expand_path('../lib', __dir__)

  def loaded_after(code)
    out = IO.popen([RbConfig.ruby, '-I', LIB, '-e', code], err: %i[child out], &:read)
    out.lines.map(&:strip)
  end

  # The login shell runs without Bundler, so bundled gems such as fiddle and
  # syslog are only reachable through a RubyGems-aware require
  def run_outside_bundler(code)
    argv = [RbConfig.ruby, '-I', LIB]
    # reline is a default gem from Ruby 2.7; before that the child, which
    # runs without Bundler, is handed the bundled copy
    if RUBY_VERSION < '2.7' && (reline = Gem.loaded_specs['reline'])
      argv += ['-I', File.join(reline.full_gem_path, 'lib')]
    end
    argv += ['-e', code]
    if defined?(Bundler)
      Bundler.with_unbundled_env { IO.popen(argv, err: %i[child out], &:read) }
    else
      IO.popen(argv, err: %i[child out], &:read)
    end.lines.map(&:strip)
  end

  def test_terminal_control_loads_fiddle_outside_bundler
    out = run_outside_bundler(<<~'RUBY')
      require 'rubish'
      Rubish::Terminal.libc
      puts :ok
    RUBY
    assert_equal ['ok'], out.grep_v(/warning/)
  end

  def test_syslog_history_loads_syslog_outside_bundler
    out = run_outside_bundler(<<~'RUBY')
      require 'rubish'
      Rubish::REPL.new.send(:log_to_syslog, 'rubish test')
      puts :ok
    RUBY
    assert_equal ['ok'], out.grep_v(/warning/)
  end

  def test_require_builtin_loads_bundled_gems_outside_bundler
    out = run_outside_bundler(<<~'RUBY')
      require 'rubish'
      repl = Rubish::REPL.new
      repl.send(:execute, 'require fiddle')
      puts defined?(Fiddle) ? :ok : :missing
    RUBY
    assert_equal ['ok'], out.grep_v(/warning/)
  end

  def test_requiring_rubish_does_not_load_single_use_libraries
    loaded = loaded_after(<<~'RUBY')
      require 'rubish'
      puts $LOADED_FEATURES.grep(%r{/(syslog|open3|fiddle)(/|\.)}).map { |f| File.basename(f) }
    RUBY
    assert_equal [], loaded, 'syslog, open3 and fiddle must be loaded on demand'
  end

  def test_terminal_control_still_works_on_demand
    loaded = loaded_after(<<~'RUBY')
      require 'rubish'
      Rubish::Terminal.get_foreground
      puts $LOADED_FEATURES.any? { |f| f.include?('fiddle') }
    RUBY
    assert_equal ['true'], loaded
  end

  def test_process_substitution_still_works
    @repl = Rubish::REPL.new
    Dir.mktmpdir('rubish_lazy') do |d|
      out = File.join(d, 'out.txt')
      execute("cat <(echo lazy) > #{out}")
      assert_equal "lazy\n", File.read(out)
    end
  end
end
