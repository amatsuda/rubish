# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Arguments may follow a redirection: `cat f > h g` reads f and g
class TestArgumentsAfterRedirection < Test::Unit::TestCase
  def test_argument_after_the_target
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      out = IO.popen([exe, '-c', 'echo a > f; echo b > g; cat f > h g; cat h; echo x >o 2>&1 y; cat o', chdir: dir, err: File::NULL], &:read)
      assert_equal "a\nb\nx y\n", out
    end
  end

  def test_builtin_argument_after_the_target
    repl = Rubish::REPL.new
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'o')
      repl.send(:execute, "echo a > #{out} b c")
      assert_equal "a b c\n", File.read(out)
    end
  end
end
