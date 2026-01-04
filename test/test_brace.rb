# frozen_string_literal: true

require_relative 'test_helper'

class TestBrace < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_brace_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Unit tests for expand_braces
  def test_expand_braces_simple_list
    result = @repl.send(:expand_braces, '{a,b,c}')
    assert_equal ['a', 'b', 'c'], result
  end

  def test_expand_braces_with_prefix
    result = @repl.send(:expand_braces, 'pre{a,b,c}')
    assert_equal ['prea', 'preb', 'prec'], result
  end

  def test_expand_braces_with_suffix
    result = @repl.send(:expand_braces, '{a,b,c}post')
    assert_equal ['apost', 'bpost', 'cpost'], result
  end

  def test_expand_braces_with_prefix_and_suffix
    result = @repl.send(:expand_braces, 'pre{a,b,c}post')
    assert_equal ['preapost', 'prebpost', 'precpost'], result
  end

  def test_expand_braces_numeric_sequence
    result = @repl.send(:expand_braces, '{1..5}')
    assert_equal ['1', '2', '3', '4', '5'], result
  end

  def test_expand_braces_numeric_sequence_reverse
    result = @repl.send(:expand_braces, '{5..1}')
    assert_equal ['5', '4', '3', '2', '1'], result
  end

  def test_expand_braces_numeric_sequence_zero_padded
    result = @repl.send(:expand_braces, '{01..05}')
    assert_equal ['01', '02', '03', '04', '05'], result
  end

  def test_expand_braces_numeric_sequence_negative
    result = @repl.send(:expand_braces, '{-2..2}')
    assert_equal ['-2', '-1', '0', '1', '2'], result
  end

  def test_expand_braces_numeric_sequence_with_step
    result = @repl.send(:expand_braces, '{1..10..2}')
    assert_equal ['1', '3', '5', '7', '9'], result
  end

  def test_expand_braces_numeric_sequence_with_step_reverse
    result = @repl.send(:expand_braces, '{10..1..2}')
    assert_equal ['10', '8', '6', '4', '2'], result
  end

  def test_expand_braces_numeric_sequence_with_step_3
    result = @repl.send(:expand_braces, '{0..10..3}')
    assert_equal ['0', '3', '6', '9'], result
  end

  def test_expand_braces_numeric_sequence_negative_step_ignored
    # Step sign is ignored, direction comes from start/end
    result = @repl.send(:expand_braces, '{1..5..-1}')
    assert_equal ['1', '2', '3', '4', '5'], result
  end

  def test_expand_braces_numeric_sequence_zero_padded_with_step
    result = @repl.send(:expand_braces, '{01..10..3}')
    assert_equal ['01', '04', '07', '10'], result
  end

  def test_expand_braces_letter_sequence
    result = @repl.send(:expand_braces, '{a..e}')
    assert_equal ['a', 'b', 'c', 'd', 'e'], result
  end

  def test_expand_braces_letter_sequence_reverse
    result = @repl.send(:expand_braces, '{e..a}')
    assert_equal ['e', 'd', 'c', 'b', 'a'], result
  end

  def test_expand_braces_letter_sequence_uppercase
    result = @repl.send(:expand_braces, '{A..E}')
    assert_equal ['A', 'B', 'C', 'D', 'E'], result
  end

  def test_expand_braces_letter_sequence_with_step
    result = @repl.send(:expand_braces, '{a..z..5}')
    assert_equal ['a', 'f', 'k', 'p', 'u', 'z'], result
  end

  def test_expand_braces_letter_sequence_with_step_reverse
    result = @repl.send(:expand_braces, '{z..a..5}')
    assert_equal ['z', 'u', 'p', 'k', 'f', 'a'], result
  end

  def test_expand_braces_letter_sequence_with_step_2
    result = @repl.send(:expand_braces, '{a..g..2}')
    assert_equal ['a', 'c', 'e', 'g'], result
  end

  def test_expand_braces_multiple_groups
    result = @repl.send(:expand_braces, '{a,b}{1,2}')
    assert_equal ['a1', 'a2', 'b1', 'b2'], result
  end

  def test_expand_braces_nested
    result = @repl.send(:expand_braces, '{a,{b,c}}')
    assert_equal ['a', 'b', 'c'], result
  end

  def test_expand_braces_no_expansion
    result = @repl.send(:expand_braces, 'hello')
    assert_equal ['hello'], result
  end

  def test_expand_braces_single_element_no_expansion
    result = @repl.send(:expand_braces, '{a}')
    assert_equal ['{a}'], result  # Single element without comma or .. is not expanded
  end

  def test_expand_braces_empty_element
    result = @repl.send(:expand_braces, '{,a,b}')
    assert_equal ['', 'a', 'b'], result
  end

  # Codegen tests
  def test_codegen_detects_brace_expansion
    codegen = Rubish::Codegen.new
    assert codegen.send(:has_brace_expansion?, '{a,b,c}')
    assert codegen.send(:has_brace_expansion?, 'file{1,2}.txt')
    assert codegen.send(:has_brace_expansion?, '{1..5}')
    assert_false codegen.send(:has_brace_expansion?, 'hello')
    assert_false codegen.send(:has_brace_expansion?, '{a}')
  end

  def test_codegen_generates_brace_call
    tokens = Rubish::Lexer.new('echo {a,b,c}').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__brace/, code)
  end

  # Execution tests with echo builtin
  def test_echo_brace_simple_list
    execute("echo {a,b,c} > #{output_file}")
    assert_equal "a b c\n", File.read(output_file)
  end

  def test_echo_brace_with_prefix_suffix
    execute("echo file{1,2,3}.txt > #{output_file}")
    assert_equal "file1.txt file2.txt file3.txt\n", File.read(output_file)
  end

  def test_echo_brace_numeric_sequence
    execute("echo {1..5} > #{output_file}")
    assert_equal "1 2 3 4 5\n", File.read(output_file)
  end

  def test_echo_brace_letter_sequence
    execute("echo {a..e} > #{output_file}")
    assert_equal "a b c d e\n", File.read(output_file)
  end

  def test_echo_brace_zero_padded
    execute("echo {01..05} > #{output_file}")
    assert_equal "01 02 03 04 05\n", File.read(output_file)
  end

  def test_echo_brace_multiple_groups
    execute("echo {a,b}{1,2} > #{output_file}")
    assert_equal "a1 a2 b1 b2\n", File.read(output_file)
  end

  def test_echo_brace_nested
    execute("echo {a,{b,c}} > #{output_file}")
    assert_equal "a b c\n", File.read(output_file)
  end

  # External command tests
  def test_external_command_brace
    execute("printf '%s\\n' {a,b,c} > #{output_file}")
    assert_equal "a\nb\nc\n", File.read(output_file)
  end

  def test_external_command_brace_with_prefix
    execute("printf '%s\\n' file{1,2}.txt > #{output_file}")
    assert_equal "file1.txt\nfile2.txt\n", File.read(output_file)
  end

  # Brace expansion with glob
  def test_brace_then_glob
    # Create some test files
    File.write(File.join(@tempdir, 'test1.txt'), 'content1')
    File.write(File.join(@tempdir, 'test2.txt'), 'content2')

    execute("ls #{@tempdir}/{test1,test2}.txt > #{output_file}")
    output = File.read(output_file)
    assert_match(/test1\.txt/, output)
    assert_match(/test2\.txt/, output)
  end

  # Quoted strings should not expand braces
  def test_single_quoted_no_brace_expansion
    execute("echo '{a,b,c}' > #{output_file}")
    assert_equal "{a,b,c}\n", File.read(output_file)
  end

  def test_double_quoted_no_brace_expansion
    execute("echo \"{a,b,c}\" > #{output_file}")
    assert_equal "{a,b,c}\n", File.read(output_file)
  end

  # Script tests
  def test_brace_in_script
    script = File.join(@tempdir, 'brace.sh')
    File.write(script, <<~SCRIPT)
      echo {1..3} > #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "1 2 3\n", File.read(output_file)
  end

  def test_brace_in_for_loop
    script = File.join(@tempdir, 'brace_for.sh')
    File.write(script, <<~SCRIPT)
      for i in {1..3}
      do
        echo $i >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1\n2\n3\n", File.read(output_file)
  end

  # Step/increment execution tests
  def test_echo_brace_numeric_step
    execute("echo {1..10..2} > #{output_file}")
    assert_equal "1 3 5 7 9\n", File.read(output_file)
  end

  def test_echo_brace_numeric_step_reverse
    execute("echo {10..1..3} > #{output_file}")
    assert_equal "10 7 4 1\n", File.read(output_file)
  end

  def test_echo_brace_letter_step
    execute("echo {a..z..5} > #{output_file}")
    assert_equal "a f k p u z\n", File.read(output_file)
  end

  def test_echo_brace_zero_padded_step
    execute("echo {001..010..2} > #{output_file}")
    assert_equal "001 003 005 007 009\n", File.read(output_file)
  end

  def test_brace_step_in_for_loop
    script = File.join(@tempdir, 'brace_step_for.sh')
    File.write(script, <<~SCRIPT)
      for i in {0..10..2}
      do
        echo $i >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "0\n2\n4\n6\n8\n10\n", File.read(output_file)
  end

  def test_brace_step_with_prefix_suffix
    execute("echo file{1..5..2}.txt > #{output_file}")
    assert_equal "file1.txt file3.txt file5.txt\n", File.read(output_file)
  end
end
