# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# A descriptor opened with `exec {var}>file` is usable as `>&$var`, can be
# duplicated from another descriptor with `{var}>&N`, and is closed with
# `exec {var}>&-`
class TestVarnameFdRedirections < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_numeric_target_reaches_the_opened_descriptor
    Dir.mktmpdir('rubish_vfd') do |dir|
      out = File.join(dir, 'out.txt')
      execute("exec {vfd_a}>#{out}; echo hi >&$vfd_a; echo st=$? >> #{out}.st; exec {vfd_a}>&-; echo x >&$vfd_a 2>/dev/null; echo after=$? >> #{out}.st")
      assert_equal "hi\n", File.read(out)
      assert_equal "st=0\nafter=1\n", File.read("#{out}.st")
    end
  end

  def test_duplicate_from_stdout
    Dir.mktmpdir('rubish_vfd') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ exec {vfd_b}>&1; echo via >&$vfd_b; exec {vfd_b}>&-; } > #{out}")
      assert_equal "via\n", File.read(out)
    end
  end
end
