# frozen_string_literal: true

require_relative 'test_helper'

class TestIFS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_ifs_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # IFS helper method tests

  def test_ifs_default_value
    ENV.delete('IFS')
    assert_equal " \t\n", Rubish::Builtins.ifs
  end

  def test_ifs_custom_value
    ENV['IFS'] = ':'
    assert_equal ':', Rubish::Builtins.ifs
  end

  def test_ifs_empty_value
    ENV['IFS'] = ''
    assert_equal '', Rubish::Builtins.ifs
  end

  def test_ifs_whitespace_default
    ENV.delete('IFS')
    assert_equal " \t\n", Rubish::Builtins.ifs_whitespace
  end

  def test_ifs_whitespace_with_colon
    ENV['IFS'] = " :\t"
    assert_equal " \t", Rubish::Builtins.ifs_whitespace
  end

  def test_ifs_non_whitespace_default
    ENV.delete('IFS')
    assert_equal '', Rubish::Builtins.ifs_non_whitespace
  end

  def test_ifs_non_whitespace_with_colon
    ENV['IFS'] = " :\t"
    assert_equal ':', Rubish::Builtins.ifs_non_whitespace
  end

  # split_by_ifs tests

  def test_split_by_ifs_default
    ENV.delete('IFS')
    result = Rubish::Builtins.split_by_ifs('  hello   world  ')
    assert_equal ['hello', 'world'], result
  end

  def test_split_by_ifs_colon
    ENV['IFS'] = ':'
    result = Rubish::Builtins.split_by_ifs('one:two:three')
    assert_equal ['one', 'two', 'three'], result
  end

  def test_split_by_ifs_colon_with_empty
    ENV['IFS'] = ':'
    result = Rubish::Builtins.split_by_ifs('one::three')
    assert_equal ['one', '', 'three'], result
  end

  def test_split_by_ifs_empty_ifs_no_split
    ENV['IFS'] = ''
    result = Rubish::Builtins.split_by_ifs('hello world')
    assert_equal ['hello world'], result
  end

  def test_split_by_ifs_mixed_whitespace_and_colon
    ENV['IFS'] = ' :'
    result = Rubish::Builtins.split_by_ifs('one two:three four')
    assert_equal ['one', 'two', 'three', 'four'], result
  end

  def test_split_by_ifs_empty_string
    ENV.delete('IFS')
    result = Rubish::Builtins.split_by_ifs('')
    assert_equal [], result
  end

  def test_split_by_ifs_nil
    ENV.delete('IFS')
    result = Rubish::Builtins.split_by_ifs(nil)
    assert_equal [], result
  end

  # split_by_ifs_n tests

  def test_split_by_ifs_n_default
    ENV.delete('IFS')
    result = Rubish::Builtins.split_by_ifs_n('one two three four', 3)
    assert_equal ['one', 'two', 'three four'], result
  end

  def test_split_by_ifs_n_colon
    ENV['IFS'] = ':'
    result = Rubish::Builtins.split_by_ifs_n('a:b:c:d', 2)
    assert_equal ['a', 'b:c:d'], result
  end

  def test_split_by_ifs_n_one_part
    ENV.delete('IFS')
    result = Rubish::Builtins.split_by_ifs_n('hello world', 1)
    assert_equal ['hello world'], result
  end

  def test_split_by_ifs_n_more_parts_than_words
    ENV.delete('IFS')
    result = Rubish::Builtins.split_by_ifs_n('one two', 5)
    assert_equal ['one', 'two'], result
  end

  # join_by_ifs tests

  def test_join_by_ifs_default
    ENV.delete('IFS')
    result = Rubish::Builtins.join_by_ifs(['one', 'two', 'three'])
    assert_equal 'one two three', result
  end

  def test_join_by_ifs_colon
    ENV['IFS'] = ':'
    result = Rubish::Builtins.join_by_ifs(['one', 'two', 'three'])
    assert_equal 'one:two:three', result
  end

  def test_join_by_ifs_empty_ifs
    ENV['IFS'] = ''
    result = Rubish::Builtins.join_by_ifs(['one', 'two', 'three'])
    assert_equal 'onetwothree', result
  end

  def test_join_by_ifs_uses_first_char_only
    ENV['IFS'] = ':;,'
    result = Rubish::Builtins.join_by_ifs(['a', 'b', 'c'])
    assert_equal 'a:b:c', result
  end

  # read builtin with IFS tests

  def test_read_with_default_ifs
    ENV.delete('IFS')
    File.write('input.txt', "hello   world   test\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      Rubish::Builtins.run_read(['a', 'b', 'c'])
    end
    $stdin = STDIN

    assert_equal 'hello', ENV['a']
    assert_equal 'world', ENV['b']
    assert_equal 'test', ENV['c']
  end

  def test_read_with_colon_ifs
    ENV['IFS'] = ':'
    File.write('input.txt', "one:two:three:four\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      Rubish::Builtins.run_read(['a', 'b', 'c'])
    end
    $stdin = STDIN

    assert_equal 'one', ENV['a']
    assert_equal 'two', ENV['b']
    assert_equal 'three:four', ENV['c']
  end

  def test_read_single_var_with_default_ifs
    ENV.delete('IFS')
    File.write('input.txt', "  hello   world  \n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      Rubish::Builtins.run_read(['result'])
    end
    $stdin = STDIN

    assert_equal 'hello   world', ENV['result']
  end

  def test_read_array_with_colon_ifs
    ENV['IFS'] = ':'
    File.write('input.txt', "a:b:c\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      Rubish::Builtins.run_read(['-a', 'arr'])
    end
    $stdin = STDIN

    assert_equal '3', ENV['arr_LENGTH']
    assert_equal 'a', ENV['arr_0']
    assert_equal 'b', ENV['arr_1']
    assert_equal 'c', ENV['arr_2']
  end

  # $* expansion with IFS tests

  def test_star_expansion_with_default_ifs
    ENV.delete('IFS')
    @repl.positional_params = ['one', 'two', 'three']

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$*\" > #{output_file}")

    assert_equal "one two three\n", File.read(output_file)
  end

  def test_star_expansion_with_colon_ifs
    ENV['IFS'] = ':'
    @repl.positional_params = ['one', 'two', 'three']

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$*\" > #{output_file}")

    assert_equal "one:two:three\n", File.read(output_file)
  end

  def test_star_expansion_with_empty_ifs
    ENV['IFS'] = ''
    @repl.positional_params = ['one', 'two', 'three']

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$*\" > #{output_file}")

    assert_equal "onetwothree\n", File.read(output_file)
  end

  def test_at_expansion_always_uses_space
    ENV['IFS'] = ':'
    @repl.positional_params = ['one', 'two', 'three']

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$@\" > #{output_file}")

    # $@ always joins with space regardless of IFS
    assert_equal "one two three\n", File.read(output_file)
  end

  # Edge cases

  def test_ifs_with_newline
    ENV['IFS'] = "\n"
    result = Rubish::Builtins.split_by_ifs("line1\nline2\nline3")
    assert_equal ['line1', 'line2', 'line3'], result
  end

  def test_ifs_with_tab
    ENV['IFS'] = "\t"
    result = Rubish::Builtins.split_by_ifs("col1\tcol2\tcol3")
    assert_equal ['col1', 'col2', 'col3'], result
  end

  def test_ifs_path_separator
    ENV['IFS'] = ':'
    result = Rubish::Builtins.split_by_ifs('/usr/bin:/bin:/usr/local/bin')
    assert_equal ['/usr/bin', '/bin', '/usr/local/bin'], result
  end

  def test_ifs_csv_like
    ENV['IFS'] = ','
    result = Rubish::Builtins.split_by_ifs('name,age,city')
    assert_equal ['name', 'age', 'city'], result
  end
end
