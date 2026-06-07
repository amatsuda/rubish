# frozen_string_literal: true

require_relative 'test_helper'

class TestMapfile < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_mapfile_test')
    @original_stdin = $stdin
    Rubish::Builtins.current_state.arrays.clear
    Rubish::Builtins.current_state.assoc_arrays.clear
  end

  def teardown
    $stdin = @original_stdin
    Rubish::Builtins.clear_mapfile_array('MAPFILE')
    Rubish::Builtins.clear_mapfile_array('myarray')
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test mapfile is a builtin
  def test_mapfile_is_builtin
    assert Rubish::Builtins.builtin?('mapfile')
  end

  # Test readarray is a builtin (alias)
  def test_readarray_is_builtin
    assert Rubish::Builtins.builtin?('readarray')
  end

  # Test mapfile reads lines into default array
  def test_mapfile_default_array
    $stdin = StringIO.new("line1\nline2\nline3\n")
    result = Rubish::Builtins.run('mapfile', [])
    assert result

    assert_equal "line1\n", Rubish::Builtins.get_array('MAPFILE')[0]
    assert_equal "line2\n", Rubish::Builtins.get_array('MAPFILE')[1]
    assert_equal "line3\n", Rubish::Builtins.get_array('MAPFILE')[2]
    assert_equal 3, Rubish::Builtins.get_array('MAPFILE').length
  end

  # Test mapfile with custom array name
  def test_mapfile_custom_array
    $stdin = StringIO.new("hello\nworld\n")
    result = Rubish::Builtins.run('mapfile', ['myarray'])
    assert result

    assert_equal "hello\n", Rubish::Builtins.get_array('myarray')[0]
    assert_equal "world\n", Rubish::Builtins.get_array('myarray')[1]
    assert_equal 2, Rubish::Builtins.get_array('myarray').length
  end

  # Test mapfile -t strips trailing newlines
  def test_mapfile_t_strips_newlines
    $stdin = StringIO.new("line1\nline2\nline3\n")
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'line1', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'line2', Rubish::Builtins.get_array('myarray')[1]
    assert_equal 'line3', Rubish::Builtins.get_array('myarray')[2]
  end

  # Test mapfile -n limits line count
  def test_mapfile_n_limits_count
    $stdin = StringIO.new("a\nb\nc\nd\ne\n")
    result = Rubish::Builtins.run('mapfile', ['-t', '-n', '3', 'myarray'])
    assert result

    assert_equal 'a', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'b', Rubish::Builtins.get_array('myarray')[1]
    assert_equal 'c', Rubish::Builtins.get_array('myarray')[2]
    assert_nil Rubish::Builtins.get_array('myarray')[3]
    assert_equal 3, Rubish::Builtins.get_array('myarray').length
  end

  # Test mapfile -s skips lines
  def test_mapfile_s_skips_lines
    $stdin = StringIO.new("skip1\nskip2\nkeep1\nkeep2\n")
    result = Rubish::Builtins.run('mapfile', ['-t', '-s', '2', 'myarray'])
    assert result

    assert_equal 'keep1', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'keep2', Rubish::Builtins.get_array('myarray')[1]
    assert_equal 2, Rubish::Builtins.get_array('myarray').length
  end

  # Test mapfile -O sets origin index
  def test_mapfile_O_sets_origin
    $stdin = StringIO.new("a\nb\nc\n")
    result = Rubish::Builtins.run('mapfile', ['-t', '-O', '5', 'myarray'])
    assert result

    assert_nil Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'a', Rubish::Builtins.get_array('myarray')[5]
    assert_equal 'b', Rubish::Builtins.get_array('myarray')[6]
    assert_equal 'c', Rubish::Builtins.get_array('myarray')[7]
  end

  # Test mapfile -d uses custom delimiter
  def test_mapfile_d_custom_delimiter
    $stdin = StringIO.new('one:two:three:')
    result = Rubish::Builtins.run('mapfile', ['-t', '-d', ':', 'myarray'])
    assert result

    assert_equal 'one', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'two', Rubish::Builtins.get_array('myarray')[1]
    assert_equal 'three', Rubish::Builtins.get_array('myarray')[2]
  end

  # Test mapfile with empty input
  def test_mapfile_empty_input
    $stdin = StringIO.new('')
    result = Rubish::Builtins.run('mapfile', ['myarray'])
    assert result
    # Should not set any array elements
    assert_nil Rubish::Builtins.get_array('myarray')[0]
  end

  # Test mapfile with single line no newline
  def test_mapfile_single_line_no_newline
    $stdin = StringIO.new('single line')
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'single line', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 1, Rubish::Builtins.get_array('myarray').length
  end

  # Test mapfile with invalid option
  def test_mapfile_invalid_option
    $stdin = StringIO.new("test\n")
    output = capture_output do
      result = Rubish::Builtins.run('mapfile', ['-z'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test mapfile -n requires argument
  def test_mapfile_n_requires_arg
    output = capture_output do
      result = Rubish::Builtins.run('mapfile', ['-n'])
      assert_false result
    end
    assert_match(/option requires an argument/, output)
  end

  # Test mapfile -d requires argument
  def test_mapfile_d_requires_arg
    output = capture_output do
      result = Rubish::Builtins.run('mapfile', ['-d'])
      assert_false result
    end
    assert_match(/option requires an argument/, output)
  end

  # Test mapfile -s requires argument
  def test_mapfile_s_requires_arg
    output = capture_output do
      result = Rubish::Builtins.run('mapfile', ['-s'])
      assert_false result
    end
    assert_match(/option requires an argument/, output)
  end

  # Test mapfile -O requires argument
  def test_mapfile_O_requires_arg
    output = capture_output do
      result = Rubish::Builtins.run('mapfile', ['-O'])
      assert_false result
    end
    assert_match(/option requires an argument/, output)
  end

  # Test mapfile combined options
  def test_mapfile_combined_options
    $stdin = StringIO.new("skip\na\nb\nc\nd\ne\n")
    result = Rubish::Builtins.run('mapfile', ['-t', '-s', '1', '-n', '3', '-O', '10', 'myarray'])
    assert result

    assert_equal 'a', Rubish::Builtins.get_array('myarray')[10]
    assert_equal 'b', Rubish::Builtins.get_array('myarray')[11]
    assert_equal 'c', Rubish::Builtins.get_array('myarray')[12]
    assert_nil Rubish::Builtins.get_array('myarray')[13]
  end

  # Test readarray is same as mapfile
  def test_readarray_works
    $stdin = StringIO.new("foo\nbar\n")
    result = Rubish::Builtins.run('readarray', ['-t', 'myarray'])
    assert result

    assert_equal 'foo', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'bar', Rubish::Builtins.get_array('myarray')[1]
  end

  # Test type identifies mapfile as builtin
  def test_type_identifies_mapfile_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['mapfile']) }
    assert_match(/mapfile is a shell builtin/, output)
  end

  # Test type identifies readarray as builtin
  def test_type_identifies_readarray_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['readarray']) }
    assert_match(/readarray is a shell builtin/, output)
  end

  # Test help for mapfile
  def test_help_mapfile
    output = capture_output { Rubish::Builtins.run('help', ['mapfile']) }
    assert_match(/mapfile:/, output)
    assert_match(/Read lines from standard input/, output)
  end

  # Test get_array helper
  def test_get_array_helper
    Rubish::Builtins.set_array('test', ['first', 'second', 'third'])

    arr = Rubish::Builtins.get_array('test')
    assert_equal ['first', 'second', 'third'], arr
  end

  # Test clear_mapfile_array helper
  def test_clear_mapfile_array_helper
    Rubish::Builtins.set_array('test', ['first', 'second'])

    Rubish::Builtins.clear_mapfile_array('test')
    assert_equal [], Rubish::Builtins.get_array('test')
  end

  # Test mapfile with lines containing spaces
  def test_mapfile_lines_with_spaces
    $stdin = StringIO.new("hello world\nfoo bar baz\n")
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'hello world', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'foo bar baz', Rubish::Builtins.get_array('myarray')[1]
  end

  # Test mapfile overwrites existing array
  def test_mapfile_overwrites_existing
    Rubish::Builtins.set_array('myarray', ['old1', 'old2', 'old3'])

    $stdin = StringIO.new("new1\nnew2\n")
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'new1', Rubish::Builtins.get_array('myarray')[0]
    assert_equal 'new2', Rubish::Builtins.get_array('myarray')[1]
    assert_nil Rubish::Builtins.get_array('myarray')[2]
    assert_equal 2, Rubish::Builtins.get_array('myarray').length
  end

  # Real-world: after mapfile, the array must be usable through normal
  # expansion (${arr[i]}, ${#arr[@]}, ${arr[*]}), not just the internal store.
  # Driven via execute() with a here-string, the way a script would.
  def test_mapfile_array_usable_via_expansion
    out = File.join(@tempdir, 'out.txt')
    $stdin = StringIO.new("x\ny\nz\n")
    execute(%(mapfile -t arr; echo "n=${#arr[@]} second=${arr[1]} all=${arr[*]}" > #{out}))
    assert_equal "n=3 second=y all=x y z\n", File.read(out)
  end

  def test_mapfile_default_keeps_delimiter
    # Without -t, each element keeps its trailing delimiter.
    out = File.join(@tempdir, 'out.txt')
    $stdin = StringIO.new("a\nb\n")
    execute(%(mapfile arr; printf '[%s]' "${arr[0]}" "${arr[1]}" > #{out}))
    assert_equal "[a\n][b\n]", File.read(out)
  end

  def test_mapfile_iterate_via_expansion
    out = File.join(@tempdir, 'out.txt')
    $stdin = StringIO.new("one\ntwo\nthree\n")
    execute(%(mapfile -t arr; for x in "${arr[@]}"; do echo "<$x>"; done > #{out}))
    assert_equal "<one>\n<two>\n<three>\n", File.read(out)
  end
end
