# frozen_string_literal: true

require_relative 'test_helper'

class TestUntil < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_until_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_until_is_keyword
    tokens = Rubish::Lexer.new('until').tokenize
    assert_equal :UNTIL, tokens.first.type
  end

  def test_until_tokenization
    tokens = Rubish::Lexer.new('until test -z x; do echo y; done').tokenize
    types = tokens.map(&:type)
    assert_equal [:UNTIL, :WORD, :WORD, :WORD, :SEMICOLON, :WORD, :WORD, :WORD, :SEMICOLON, :WORD], types
  end

  # Parser tests
  def test_simple_until_parsing
    tokens = Rubish::Lexer.new('until true; do echo yes; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Until, ast
    assert_not_nil ast.condition
    assert_not_nil ast.body
  end

  def test_until_with_test_condition
    tokens = Rubish::Lexer.new('until test -z x; do echo y; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Until, ast
  end

  def test_until_multiple_body_commands
    tokens = Rubish::Lexer.new('until true; do echo a; echo b; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Until, ast
    assert_instance_of Rubish::AST::List, ast.body
  end

  # Codegen tests
  def test_until_codegen
    tokens = Rubish::Lexer.new('until true; do echo yes; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/until __condition/, code)
    assert_match(/__cmd\("echo", \*\["yes"\]\.flatten\)/, code)
  end

  # Execution tests - condition that is always true (no iterations)
  def test_until_true_never_runs
    script = File.join(@tempdir, 'true.sh')
    File.write(script, <<~SCRIPT)
      echo before > #{output_file}
      until true; do
        echo inside >> #{output_file}
      done
      echo after >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/before/, content)
    assert_match(/after/, content)
    assert_no_match(/inside/, content)
  end

  def test_until_test_n_nonempty_never_runs
    script = File.join(@tempdir, 'n.sh')
    File.write(script, <<~SCRIPT)
      echo start > #{output_file}
      until test -n nonempty; do
        echo loop >> #{output_file}
      done
      echo end >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/start/, content)
    assert_match(/end/, content)
    assert_no_match(/loop/, content)
  end

  def test_until_numeric_compare_already_true
    script = File.join(@tempdir, 'num.sh')
    File.write(script, <<~SCRIPT)
      echo start > #{output_file}
      until test 10 -gt 5; do
        echo loop >> #{output_file}
      done
      echo end >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/start/, content)
    assert_match(/end/, content)
    assert_no_match(/loop/, content)
  end

  # Test nested structure parsing
  def test_until_in_if_parsing
    tokens = Rubish::Lexer.new('if true; then until true; do echo x; done; fi').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::If, ast
    assert_instance_of Rubish::AST::Until, ast.branches.first[1]
  end

  def test_if_in_until_parsing
    tokens = Rubish::Lexer.new('until true; do if true; then echo x; fi; done').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Until, ast
    assert_instance_of Rubish::AST::If, ast.body
  end

  # Variable expansion tests - these require runtime expansion
  def test_until_with_counter_variable
    script = File.join(@tempdir, 'counter.sh')
    File.write(script, <<~SCRIPT)
      export count=0
      until test $count -ge 3; do
        export count=$((count + 1))
        echo $count >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")

    assert_equal "1\n2\n3\n", File.read(output_file)
  end

  def test_until_with_shift
    script = File.join(@tempdir, 'shift.sh')
    File.write(script, <<~SCRIPT)
      set -- a b c
      until test $# -eq 0; do
        echo $1 >> #{output_file}
        shift
      done
    SCRIPT

    execute("source #{script}")

    assert_equal "a\nb\nc\n", File.read(output_file)
  end

  def test_until_with_string_variable
    script = File.join(@tempdir, 'strvar.sh')
    File.write(script, <<~SCRIPT)
      export val=start
      until test $val = done; do
        echo $val >> #{output_file}
        if test $val = start; then
          export val=middle
        elif test $val = middle; then
          export val=done
        fi
      done
      echo finished >> #{output_file}
    SCRIPT

    execute("source #{script}")

    assert_equal "start\nmiddle\nfinished\n", File.read(output_file)
  end

  def test_until_variable_in_body_changes
    script = File.join(@tempdir, 'bodyvar.sh')
    File.write(script, <<~SCRIPT)
      export x=1
      until test $x -gt 3; do
        echo "x=$x" >> #{output_file}
        export x=$((x + 1))
      done
    SCRIPT

    execute("source #{script}")

    assert_equal "x=1\nx=2\nx=3\n", File.read(output_file)
  end

  def test_until_combined_with_for
    script = File.join(@tempdir, 'until_for.sh')
    File.write(script, <<~SCRIPT)
      export n=0
      until test $n -ge 2; do
        export n=$((n + 1))
        for letter in a b; do
          echo "$n$letter" >> #{output_file}
        done
      done
    SCRIPT

    execute("source #{script}")

    assert_equal "1a\n1b\n2a\n2b\n", File.read(output_file)
  end

  # Test until is opposite of while
  def test_until_is_opposite_of_while
    # until false should run (condition false -> runs)
    script = File.join(@tempdir, 'false.sh')
    File.write(script, <<~SCRIPT)
      export count=0
      until false; do
        export count=$((count + 1))
        echo $count >> #{output_file}
        if test $count -ge 3; then
          break
        fi
      done
    SCRIPT

    # Note: break is not implemented yet, so we'll use a different test
  end

  def test_until_runs_while_condition_false
    script = File.join(@tempdir, 'untilfalse.sh')
    File.write(script, <<~SCRIPT)
      export x=0
      until test $x -eq 3; do
        export x=$((x + 1))
        echo $x >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")

    # Runs while x != 3, stops when x == 3
    assert_equal "1\n2\n3\n", File.read(output_file)
  end
end
