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
