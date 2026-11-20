# frozen_string_literal: true

require_relative 'test_helper'

# read: clustered short options (-ra) and IFS from a prefix assignment
class TestReadIfsAndFlags < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    Rubish::Builtins.unset(%w[p q parts IFS])
  end

  def test_clustered_flags_with_array
    execute('read -ra parts <<< "a b c"')
    assert_equal %w[a b c], Rubish::Builtins.get_array('parts')
  end

  def test_prefix_ifs_applies_to_herestring_read
    execute('IFS=: read -r p q <<< "a:b"')
    assert_equal 'a', get_shell_var('p')
    assert_equal 'b', get_shell_var('q')
  end

  def test_prefix_ifs_does_not_leak
    execute('IFS=: read -r p q <<< "a:b"')
    assert_nil get_shell_var('IFS')
  end

  def test_prefix_ifs_with_clustered_array_flag
    execute('IFS=, read -ra parts <<< "a,b,c"')
    assert_equal %w[a b c], Rubish::Builtins.get_array('parts')
  end

  def test_shell_ifs_applies_to_array_read
    execute('IFS=,; read -ra parts <<< "x,y"')
    assert_equal %w[x y], Rubish::Builtins.get_array('parts')
  end

  def test_prefix_ifs_overrides_shell_ifs
    execute('IFS=,; IFS=: read -r p q <<< "a:b,c"')
    assert_equal 'a', get_shell_var('p')
    assert_equal 'b,c', get_shell_var('q')
  end

  def test_clustered_flag_with_attached_value
    execute('read -rn2 p <<< "abcd"')
    assert_equal 'ab', get_shell_var('p')
  end
end
