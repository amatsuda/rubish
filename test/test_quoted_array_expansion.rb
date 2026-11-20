# frozen_string_literal: true

require_relative 'test_helper'

# "${arr[@]}" must expand to one word per element, like "$@"
class TestQuotedArrayExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_quoted_array')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    execute('arr=("a b" c "")')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.unset(['arr'])
  end

  def output
    File.read(File.join(@tempdir, 'out.txt'))
  end

  def test_quoted_at_keeps_elements_for_external_command
    execute('/usr/bin/printf "[%s]" "${arr[@]}" > out.txt')
    assert_equal '[a b][c][]', output
  end

  def test_quoted_at_keeps_elements_for_builtin
    out = capture_stdout { execute('printf "[%s]" "${arr[@]}"') }
    assert_equal '[a b][c][]', out
  end

  def test_quoted_at_keeps_elements_in_for_loop
    out = capture_stdout { execute('for i in "${arr[@]}"; do echo "<$i>"; done') }
    assert_equal "<a b>\n<c>\n<>\n", out
  end

  def test_quoted_star_joins_into_single_word
    out = capture_stdout { execute('printf "[%s]" "${arr[*]}"') }
    assert_equal '[a b c ]', out
  end

  def test_quoted_at_with_adjacent_text_attaches_to_first_and_last
    out = capture_stdout { execute('printf "[%s]" "x${arr[@]}y"') }
    assert_equal '[xa b][c][y]', out
  end

  def test_quoted_at_of_empty_array_expands_to_nothing
    execute('empty=()')
    out = capture_stdout { execute('printf "[%s]" "${empty[@]}"') }
    assert_equal '[]', out
  end

  def test_quoted_keys_expansion_keeps_one_word_per_key
    execute('declare -A map; map["k 1"]=a; map[k2]=b')
    out = capture_stdout { execute('for k in "${!map[@]}"; do echo "<$k>"; done') }
    assert_equal ['<k 1>', '<k2>'], out.lines(chomp: true).sort
  end

  def test_quoted_literal_in_for_loop_strips_quotes
    out = capture_stdout { execute('for i in "a b" c; do echo "<$i>"; done') }
    assert_equal "<a b>\n<c>\n", out
  end
end
