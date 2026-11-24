# frozen_string_literal: true

require_relative 'test_helper'

# An alias whose text starts with another alias expands both, as in bash
class TestAliasChain < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_chain
    assert_equal "z\n", run_shell(%q{shopt -s expand_aliases; alias x='echo'; alias y='x'; eval 'y z'})
  end

  def test_self_reference_stops
    assert_equal "ok\n", run_shell(%q{shopt -s expand_aliases; alias echo='echo ok'; eval 'echo'})
  end
end
