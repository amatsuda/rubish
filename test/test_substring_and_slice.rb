# frozen_string_literal: true

require_relative 'test_helper'

# ${var:offset:length} with arithmetic/negative offsets and ${arr[@]:offset:length}
class TestSubstringAndSlice < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('s=hello; a=(x y z w); i=1')
  end

  def teardown
    Rubish::Builtins.unset(%w[s a i])
  end

  def echo(expr)
    capture_stdout { execute("echo #{expr}") }.chomp
  end

  def test_quoted_whole_word_substring_in_builtin_path
    assert_equal 'h', echo('"${s:0:1}"')
    assert_equal 'ell', echo('"${s:1:3}"')
  end

  def test_negative_offset_forms
    assert_equal 'llo', echo('"${s:(-3)}"')
    assert_equal 'lo', echo('"${s: -2}"')
    assert_equal 'll', echo('"${s: -3:2}"')
  end

  def test_negative_length_means_up_to_that_many_from_end
    assert_equal 'ell', echo('"${s:1:-1}"')
  end

  def test_arithmetic_offset
    assert_equal 'llo', echo('"${s:i+1}"')
    assert_equal 'lo', echo('"${s:$((i+2))}"')
  end

  def test_offset_past_end_is_empty
    assert_equal '', echo('"${s:10}"')
  end

  def test_array_slice_unquoted
    assert_equal 'y z w', echo('${a[@]:1}')
    assert_equal 'y z', echo('${a[@]:1:2}')
    assert_equal 'w', echo('${a[@]: -1}')
  end

  def test_array_slice_quoted_keeps_elements
    out = capture_stdout { execute('printf "[%s]" "${a[@]:1:2}"; echo') }
    assert_equal "[y][z]\n", out
  end

  def test_array_slice_star_joins
    assert_equal 'x y', echo('"${a[*]:0:2}"')
  end

  def test_array_slice_in_for_loop
    out = capture_stdout { execute('for e in "${a[@]:2}"; do echo "<$e>"; done') }
    assert_equal "<z>\n<w>\n", out
  end

  def test_positional_slice
    out = capture_stdout { execute('set -- p q r s; echo "${@:2:2}"') }
    assert_equal "q r\n", out
  end

  def test_external_command_sees_substring
    Dir.mktmpdir('rubish_substring') do |dir|
      out = File.join(dir, 'out.txt')
      execute("/usr/bin/printf '%s|%s' \"${s:1:2}\" \"${a[@]:3}\" > #{out}")
      assert_equal 'el|w', File.read(out)
    end
  end
end
