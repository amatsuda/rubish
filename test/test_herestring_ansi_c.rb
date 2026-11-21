# frozen_string_literal: true

require_relative 'test_helper'

# The here-string word may be ANSI-C quoted and contain spaces
class TestHerestringAnsiC < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_ansi_c_quoted_herestring_with_spaces_and_newlines
    execute(%q(read -r -a parts_hs -d '' <<< $'a b\nc'))
    assert_equal 'c', Rubish::Builtins.get_array_element('parts_hs', 2)
    assert_equal 3, Rubish::Builtins.array_length('parts_hs')
  end

  def test_double_quoted_herestring_with_spaces
    execute('read -r hs_line <<< "two words"')
    assert_equal 'two words', get_shell_var('hs_line')
  end
end
