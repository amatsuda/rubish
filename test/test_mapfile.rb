# frozen_string_literal: true

require_relative 'test_helper'

class TestMapfile < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_mapfile_test')
    @original_stdin = $stdin
    Rubish::Builtins.clear_mapfile_array('MAPFILE')
    Rubish::Builtins.clear_mapfile_array('myarray')
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

    assert_equal "line1\n", ENV['MAPFILE_0']
    assert_equal "line2\n", ENV['MAPFILE_1']
    assert_equal "line3\n", ENV['MAPFILE_2']
    assert_equal '3', ENV['MAPFILE_LENGTH']
  end

  # Test mapfile with custom array name
  def test_mapfile_custom_array
    $stdin = StringIO.new("hello\nworld\n")
    result = Rubish::Builtins.run('mapfile', ['myarray'])
    assert result

    assert_equal "hello\n", ENV['myarray_0']
    assert_equal "world\n", ENV['myarray_1']
    assert_equal '2', ENV['myarray_LENGTH']
  end

  # Test mapfile -t strips trailing newlines
  def test_mapfile_t_strips_newlines
    $stdin = StringIO.new("line1\nline2\nline3\n")
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'line1', ENV['myarray_0']
    assert_equal 'line2', ENV['myarray_1']
    assert_equal 'line3', ENV['myarray_2']
  end

  # Test mapfile -n limits line count
  def test_mapfile_n_limits_count
    $stdin = StringIO.new("a\nb\nc\nd\ne\n")
    result = Rubish::Builtins.run('mapfile', ['-t', '-n', '3', 'myarray'])
    assert result

    assert_equal 'a', ENV['myarray_0']
    assert_equal 'b', ENV['myarray_1']
    assert_equal 'c', ENV['myarray_2']
    assert_nil ENV['myarray_3']
    assert_equal '3', ENV['myarray_LENGTH']
  end

  # Test mapfile -s skips lines
  def test_mapfile_s_skips_lines
    $stdin = StringIO.new("skip1\nskip2\nkeep1\nkeep2\n")
    result = Rubish::Builtins.run('mapfile', ['-t', '-s', '2', 'myarray'])
    assert result

    assert_equal 'keep1', ENV['myarray_0']
    assert_equal 'keep2', ENV['myarray_1']
    assert_equal '2', ENV['myarray_LENGTH']
  end

  # Test mapfile -O sets origin index
  def test_mapfile_O_sets_origin
    $stdin = StringIO.new("a\nb\nc\n")
    result = Rubish::Builtins.run('mapfile', ['-t', '-O', '5', 'myarray'])
    assert result

    assert_nil ENV['myarray_0']
    assert_equal 'a', ENV['myarray_5']
    assert_equal 'b', ENV['myarray_6']
    assert_equal 'c', ENV['myarray_7']
  end

  # Test mapfile -d uses custom delimiter
  def test_mapfile_d_custom_delimiter
    $stdin = StringIO.new('one:two:three:')
    result = Rubish::Builtins.run('mapfile', ['-t', '-d', ':', 'myarray'])
    assert result

    assert_equal 'one', ENV['myarray_0']
    assert_equal 'two', ENV['myarray_1']
    assert_equal 'three', ENV['myarray_2']
  end

  # Test mapfile with empty input
  def test_mapfile_empty_input
    $stdin = StringIO.new('')
    result = Rubish::Builtins.run('mapfile', ['myarray'])
    assert result
    # Should not set any array elements
    assert_nil ENV['myarray_0']
  end

  # Test mapfile with single line no newline
  def test_mapfile_single_line_no_newline
    $stdin = StringIO.new('single line')
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'single line', ENV['myarray_0']
    assert_equal '1', ENV['myarray_LENGTH']
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

    assert_equal 'a', ENV['myarray_10']
    assert_equal 'b', ENV['myarray_11']
    assert_equal 'c', ENV['myarray_12']
    assert_nil ENV['myarray_13']
  end

  # Test readarray is same as mapfile
  def test_readarray_works
    $stdin = StringIO.new("foo\nbar\n")
    result = Rubish::Builtins.run('readarray', ['-t', 'myarray'])
    assert result

    assert_equal 'foo', ENV['myarray_0']
    assert_equal 'bar', ENV['myarray_1']
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

  # Test get_mapfile_array helper
  def test_get_mapfile_array_helper
    ENV['test_0'] = 'first'
    ENV['test_1'] = 'second'
    ENV['test_2'] = 'third'
    ENV['test_LENGTH'] = '3'

    arr = Rubish::Builtins.get_mapfile_array('test')
    assert_equal ['first', 'second', 'third'], arr
  end

  # Test clear_mapfile_array helper
  def test_clear_mapfile_array_helper
    ENV['test_0'] = 'first'
    ENV['test_1'] = 'second'
    ENV['test_LENGTH'] = '2'

    Rubish::Builtins.clear_mapfile_array('test')
    assert_nil ENV['test_0']
    assert_nil ENV['test_1']
    assert_nil ENV['test_LENGTH']
  end

  # Test mapfile with lines containing spaces
  def test_mapfile_lines_with_spaces
    $stdin = StringIO.new("hello world\nfoo bar baz\n")
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'hello world', ENV['myarray_0']
    assert_equal 'foo bar baz', ENV['myarray_1']
  end

  # Test mapfile overwrites existing array
  def test_mapfile_overwrites_existing
    ENV['myarray_0'] = 'old1'
    ENV['myarray_1'] = 'old2'
    ENV['myarray_2'] = 'old3'
    ENV['myarray_LENGTH'] = '3'

    $stdin = StringIO.new("new1\nnew2\n")
    result = Rubish::Builtins.run('mapfile', ['-t', 'myarray'])
    assert result

    assert_equal 'new1', ENV['myarray_0']
    assert_equal 'new2', ENV['myarray_1']
    assert_nil ENV['myarray_2']
    assert_equal '2', ENV['myarray_LENGTH']
  end
end
