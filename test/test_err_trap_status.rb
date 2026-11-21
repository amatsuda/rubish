# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Inside an ERR trap handler, $? is the status of the command that failed
class TestErrTrapStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('trap - ERR')
  end

  def test_handler_sees_the_failing_status
    Dir.mktmpdir('rubish_err') do |dir|
      out = File.join(dir, 'out.txt')
      execute("trap 'echo ERR:$? >> #{out}' ERR")
      execute('false')
      execute('(exit 3)')
      execute('true')
      assert_equal "ERR:1\nERR:3\n", File.read(out)
    end
  end
end
