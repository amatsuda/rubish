# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `{arr[i]}>file` and `exec {arr[i]}>&-` address an array element, as bash
# allows for the coproc descriptors
class TestSubscriptedVarnameRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_open_and_close_through_an_array_element
    Dir.mktmpdir('rubish_svr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("exec {fds_s[1]}>#{out}; echo \"n=${fds_s[1]}\" >&${fds_s[1]}; exec {fds_s[1]}>&-; echo x >&${fds_s[1]} 2>/dev/null; echo closed=$? >> #{out}")
      content = File.read(out)
      assert_match(/\An=\d+\nclosed=1\n\z/, content)
    end
  end
end
