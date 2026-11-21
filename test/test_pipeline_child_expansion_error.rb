# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

class TestPipelineChildExpansionError < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_idiom') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  # ${1:?msg} failing inside a piped function is a diagnostic with status 127,
  # not a Ruby traceback from the forked pipeline element
  def test_parameter_error_in_pipeline_child
    exe = File.expand_path('../exe/rubish', __dir__)
    lib = File.expand_path('../lib', __dir__)
    out = IO.popen([RbConfig.ruby, '-I', lib, exe, '-c', %q{f() { local n="${1:?need an argument}"; echo "$n"; }; f 2>&1 | cat; echo "rc=${PIPESTATUS[0]}"}], err: %i[child out], &:read)
    assert_no_match(/\.rb:\d+:in/, out)
    assert_match(/need an argument/, out)
    assert_match(/rc=127/, out)
  end
end
