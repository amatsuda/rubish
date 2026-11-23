# frozen_string_literal: true

require_relative 'test_helper'

# type knows the shell's reserved words
class TestTypeKeyword < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_type_t_keyword
    out = capture_stdout { execute('type -t if while fi; echo $?') }
    assert_equal "keyword\nkeyword\nkeyword\n0\n", out
  end

  def test_type_keyword_description
    out = capture_stdout { execute('type for') }
    assert_equal "for is a shell keyword\n", out
  end
end
