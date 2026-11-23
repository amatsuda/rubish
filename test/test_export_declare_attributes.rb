# frozen_string_literal: true

require_relative 'test_helper'

# declare +x removes the export attribute and takes the name out of the environment
class TestExportDeclareAttributes < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('unset XD')
  end

  def test_declare_plus_x_unexports
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'declare -x XD=1; env | grep -c "^XD=1"; declare +x XD; env | grep -c "^XD=1"; echo $XD'], &:read)
    assert_equal "1\n0\n1\n", out
  end
end
