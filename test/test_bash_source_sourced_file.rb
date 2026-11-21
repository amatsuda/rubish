# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# BASH_SOURCE[0] names the file being sourced, outside any function too
class TestBashSourceSourcedFile < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_bash_source_in_sourced_file
    Dir.mktmpdir('rubish_src') do |dir|
      script = File.join(dir, 'lib.sh')
      out = File.join(dir, 'out.txt')
      File.write(script, "echo \"src=${BASH_SOURCE[0]##*/} n=${#BASH_SOURCE[@]}\" > #{out}\n")
      execute("source #{script}")
      assert_equal "src=lib.sh n=1\n", File.read(out)
    end
  end

  def test_bash_source_is_empty_outside_a_script
    out = capture_stdout { execute('echo "[${BASH_SOURCE[0]}]"') }
    assert_equal "[]\n", out
  end
end
