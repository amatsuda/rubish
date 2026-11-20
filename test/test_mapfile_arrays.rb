# frozen_string_literal: true

require_relative 'test_helper'

# mapfile/readarray store into a real indexed array readable via ${arr[@]}
class TestMapfileArrays < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir('rubish_mapfile')
    @file = File.join(@dir, 'in.txt')
    File.write(@file, "one\ntwo\nthree\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
    Rubish::Builtins.unset(%w[lines MAPFILE])
  end

  def test_herestring_input
    execute(%q(mapfile -t lines <<< $'x\ny'))
    assert_equal %w[x y], Rubish::Builtins.get_array('lines')
    out = capture_stdout { execute('echo "${#lines[@]}:${lines[1]}"') }
    assert_equal "2:y\n", out
  end

  def test_file_input_keeps_newlines_without_t
    execute("mapfile lines < #{@file}")
    assert_equal ["one\n", "two\n", "three\n"], Rubish::Builtins.get_array('lines')
  end

  def test_readarray_alias_and_default_name
    execute("readarray -t < #{@file}")
    assert_equal %w[one two three], Rubish::Builtins.get_array('MAPFILE')
  end

  def test_origin_and_skip
    execute('lines=(a b c d)')
    execute("mapfile -t -O 1 -s 1 lines < #{@file}")
    assert_equal %w[a two three], Rubish::Builtins.get_array('lines')
  end

  def test_count_limit
    execute("mapfile -t -n 2 lines < #{@file}")
    assert_equal %w[one two], Rubish::Builtins.get_array('lines')
  end
end
