# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

class TestRedirectFromProcessSubstitution < Test::Unit::TestCase
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

  # `cmd < <(other)`: process substitution as the input redirect target
  def test_input_redirect_from_process_substitution
    assert_equal "2 y\n", run_and_read("mapfile -t pl < <(printf 'x\\ny\\n'); echo \"${#pl[@]} ${pl[1]}\"")
  end
end
