# frozen_string_literal: true

require_relative 'test_helper'

class TestCompVariables < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_comp_test')
    Dir.chdir(@tempdir)
    Rubish::Builtins.clear_completions
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.clear_completion_context
    Rubish::Builtins.clear_completions
  end

  # COMP_WORDBREAKS tests

  def test_comp_wordbreaks_default
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$COMP_WORDBREAKS\" > #{output_file}")
    value = File.read(output_file).chomp  # Use chomp, not strip (preserves leading space)
    # Default includes space, tab, newline, and special chars
    assert value.include?(' '), 'COMP_WORDBREAKS should include space'
  end

  def test_comp_wordbreaks_can_be_set
    ENV['COMP_WORDBREAKS'] = ' ='
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"$COMP_WORDBREAKS\" > #{output_file}")
    value = File.read(output_file).chomp  # Use chomp, not strip (preserves leading space)
    assert_equal ' =', value
  end

  # Completion context tests

  def test_comp_line_set_in_context
    Rubish::Builtins.set_completion_context(
      line: 'git status',
      point: 10,
      words: ['git', 'status'],
      cword: 1
    )
    assert_equal 'git status', Rubish::Builtins.comp_line
  end

  def test_comp_point_set_in_context
    Rubish::Builtins.set_completion_context(
      line: 'git status',
      point: 10,
      words: ['git', 'status'],
      cword: 1
    )
    assert_equal 10, Rubish::Builtins.comp_point
  end

  def test_comp_words_set_in_context
    Rubish::Builtins.set_completion_context(
      line: 'git status file.txt',
      point: 19,
      words: ['git', 'status', 'file.txt'],
      cword: 2
    )
    assert_equal ['git', 'status', 'file.txt'], Rubish::Builtins.comp_words
  end

  def test_comp_cword_set_in_context
    Rubish::Builtins.set_completion_context(
      line: 'git status',
      point: 10,
      words: ['git', 'status'],
      cword: 1
    )
    assert_equal 1, Rubish::Builtins.comp_cword
  end

  def test_comp_type_default
    Rubish::Builtins.set_completion_context(
      line: 'cmd',
      point: 3,
      words: ['cmd'],
      cword: 0
    )
    assert_equal 9, Rubish::Builtins.comp_type  # TAB = 9
  end

  def test_comp_key_default
    Rubish::Builtins.set_completion_context(
      line: 'cmd',
      point: 3,
      words: ['cmd'],
      cword: 0
    )
    assert_equal 9, Rubish::Builtins.comp_key  # TAB = 9
  end

  def test_context_cleared
    Rubish::Builtins.set_completion_context(
      line: 'git status',
      point: 10,
      words: ['git', 'status'],
      cword: 1
    )
    Rubish::Builtins.clear_completion_context
    assert_equal '', Rubish::Builtins.comp_line
    assert_equal 0, Rubish::Builtins.comp_point
    assert_equal [], Rubish::Builtins.comp_words
    assert_equal 0, Rubish::Builtins.comp_cword
  end

  # COMPREPLY tests

  def test_compreply_initially_empty
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#COMPREPLY[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  def test_compreply_can_be_set
    execute('COMPREPLY=(one two three)')
    assert_equal ['one', 'two', 'three'], Rubish::Builtins.compreply
  end

  def test_compreply_can_be_appended
    execute('COMPREPLY=(one)')
    execute('COMPREPLY+=(two three)')
    assert_equal ['one', 'two', 'three'], Rubish::Builtins.compreply
  end

  def test_compreply_element_access
    Rubish::Builtins.compreply = ['foo', 'bar', 'baz']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COMPREPLY[1]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'bar', value
  end

  def test_compreply_all_elements
    Rubish::Builtins.compreply = ['foo', 'bar', 'baz']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COMPREPLY[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'foo bar baz', value
  end

  def test_compreply_length
    Rubish::Builtins.compreply = ['foo', 'bar', 'baz']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#COMPREPLY[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_compreply_keys
    Rubish::Builtins.compreply = ['foo', 'bar', 'baz']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!COMPREPLY[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 1 2', value
  end

  def test_compreply_element_assignment
    Rubish::Builtins.compreply = ['foo', 'bar', 'baz']
    execute('COMPREPLY[1]=changed')
    assert_equal ['foo', 'changed', 'baz'], Rubish::Builtins.compreply
  end

  # COMP_WORDS array tests

  def test_comp_words_element_access
    Rubish::Builtins.comp_words = ['git', 'commit', '-m']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COMP_WORDS[0]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'git', value
  end

  def test_comp_words_all_elements
    Rubish::Builtins.comp_words = ['git', 'commit', '-m']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COMP_WORDS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'git commit -m', value
  end

  def test_comp_words_length
    Rubish::Builtins.comp_words = ['git', 'commit', '-m']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#COMP_WORDS[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_comp_words_keys
    Rubish::Builtins.comp_words = ['git', 'commit', '-m']
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!COMP_WORDS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 1 2', value
  end

  # Read-only tests

  def test_comp_line_is_read_only
    Rubish::Builtins.comp_line = 'original'
    execute('COMP_LINE=modified')
    # Assignment should be ignored
    assert_equal 'original', Rubish::Builtins.comp_line
  end

  def test_comp_point_is_read_only
    Rubish::Builtins.comp_point = 10
    execute('COMP_POINT=99')
    assert_equal 10, Rubish::Builtins.comp_point
  end

  def test_comp_cword_is_read_only
    Rubish::Builtins.comp_cword = 2
    execute('COMP_CWORD=99')
    assert_equal 2, Rubish::Builtins.comp_cword
  end

  def test_comp_type_is_read_only
    Rubish::Builtins.comp_type = 9
    execute('COMP_TYPE=99')
    assert_equal 9, Rubish::Builtins.comp_type
  end

  def test_comp_key_is_read_only
    Rubish::Builtins.comp_key = 9
    execute('COMP_KEY=99')
    assert_equal 9, Rubish::Builtins.comp_key
  end

  def test_comp_words_is_read_only
    Rubish::Builtins.comp_words = ['original']
    execute('COMP_WORDS=modified')
    assert_equal ['original'], Rubish::Builtins.comp_words
  end

  # Variable expansion tests

  def test_comp_line_expansion
    Rubish::Builtins.comp_line = 'test command'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $COMP_LINE > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'test command', value
  end

  def test_comp_point_expansion
    Rubish::Builtins.comp_point = 42
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $COMP_POINT > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '42', value
  end

  def test_comp_cword_expansion
    Rubish::Builtins.comp_cword = 3
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $COMP_CWORD > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '3', value
  end

  def test_comp_type_expansion
    Rubish::Builtins.comp_type = 33
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $COMP_TYPE > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '33', value
  end

  def test_comp_key_expansion
    Rubish::Builtins.comp_key = 63
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $COMP_KEY > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '63', value
  end

  # split_completion_words helper tests

  def test_split_completion_words_simple
    words = @repl.send(:split_completion_words, 'git status')
    assert_equal ['git', 'status'], words
  end

  def test_split_completion_words_with_quotes
    words = @repl.send(:split_completion_words, 'echo "hello world"')
    assert_equal ['echo', '"hello world"'], words
  end

  def test_split_completion_words_multiple_spaces
    words = @repl.send(:split_completion_words, 'git   status')
    assert_equal ['git', 'status'], words
  end

  def test_split_completion_words_empty
    words = @repl.send(:split_completion_words, '')
    assert_equal [], words
  end
end
