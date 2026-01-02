# frozen_string_literal: true

require_relative 'test_helper'

class TestBreakContinue < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_break_continue_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Break tests - while loop
  def test_break_in_while
    script = File.join(@tempdir, 'break_while.sh')
    File.write(script, <<~SCRIPT)
      export n=0
      while true; do
        export n=$((n + 1))
        echo $n >> #{output_file}
        if test $n -ge 3; then
          break
        fi
      done
      echo done >> #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "1\n2\n3\ndone\n", File.read(output_file)
  end

  def test_break_exits_immediately
    script = File.join(@tempdir, 'break_exit.sh')
    File.write(script, <<~SCRIPT)
      for i in 1 2 3 4 5; do
        if test $i -eq 3; then
          break
        fi
        echo $i >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1\n2\n", File.read(output_file)
  end

  # Break tests - for loop
  def test_break_in_for
    script = File.join(@tempdir, 'break_for.sh')
    File.write(script, <<~SCRIPT)
      for x in a b c d e; do
        echo $x >> #{output_file}
        if test $x = c; then
          break
        fi
      done
      echo end >> #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "a\nb\nc\nend\n", File.read(output_file)
  end

  # Break tests - until loop
  def test_break_in_until
    script = File.join(@tempdir, 'break_until.sh')
    File.write(script, <<~SCRIPT)
      export n=0
      until false; do
        export n=$((n + 1))
        echo $n >> #{output_file}
        if test $n -ge 3; then
          break
        fi
      done
      echo done >> #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "1\n2\n3\ndone\n", File.read(output_file)
  end

  # Continue tests - while loop
  def test_continue_in_while
    script = File.join(@tempdir, 'continue_while.sh')
    File.write(script, <<~SCRIPT)
      export n=0
      while test $n -lt 5; do
        export n=$((n + 1))
        if test $n -eq 3; then
          continue
        fi
        echo $n >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1\n2\n4\n5\n", File.read(output_file)
  end

  # Continue tests - for loop
  def test_continue_in_for
    script = File.join(@tempdir, 'continue_for.sh')
    File.write(script, <<~SCRIPT)
      for x in a b c d e; do
        if test $x = c; then
          continue
        fi
        echo $x >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "a\nb\nd\ne\n", File.read(output_file)
  end

  # Continue tests - until loop
  def test_continue_in_until
    script = File.join(@tempdir, 'continue_until.sh')
    File.write(script, <<~SCRIPT)
      export n=0
      until test $n -ge 5; do
        export n=$((n + 1))
        if test $n -eq 3; then
          continue
        fi
        echo $n >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1\n2\n4\n5\n", File.read(output_file)
  end

  # Continue skips to next iteration
  def test_continue_skips_rest_of_body
    script = File.join(@tempdir, 'continue_skip.sh')
    File.write(script, <<~SCRIPT)
      for i in 1 2 3; do
        echo before$i >> #{output_file}
        if test $i -eq 2; then
          continue
        fi
        echo after$i >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "before1\nafter1\nbefore2\nbefore3\nafter3\n", File.read(output_file)
  end

  # Nested loops - break only affects innermost
  def test_break_in_nested_loop
    script = File.join(@tempdir, 'break_nested.sh')
    File.write(script, <<~SCRIPT)
      for i in 1 2; do
        echo outer$i >> #{output_file}
        for j in a b c; do
          if test $j = b; then
            break
          fi
          echo inner$j >> #{output_file}
        done
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "outer1\ninnera\nouter2\ninnera\n", File.read(output_file)
  end

  # Nested loops - continue only affects innermost
  def test_continue_in_nested_loop
    script = File.join(@tempdir, 'continue_nested.sh')
    File.write(script, <<~SCRIPT)
      for i in 1 2; do
        for j in a b c; do
          if test $j = b; then
            continue
          fi
          echo $i$j >> #{output_file}
        done
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1a\n1c\n2a\n2c\n", File.read(output_file)
  end

  # Break N - break out of N levels
  def test_break_2_levels
    script = File.join(@tempdir, 'break2.sh')
    File.write(script, <<~SCRIPT)
      for i in 1 2 3; do
        for j in a b c; do
          echo $i$j >> #{output_file}
          if test $j = b; then
            break 2
          fi
        done
        echo outer >> #{output_file}
      done
      echo done >> #{output_file}
    SCRIPT

    execute("source #{script}")
    assert_equal "1a\n1b\ndone\n", File.read(output_file)
  end

  # Continue N - continue Nth enclosing loop
  def test_continue_2_levels
    script = File.join(@tempdir, 'continue2.sh')
    File.write(script, <<~SCRIPT)
      for i in 1 2 3; do
        for j in a b c; do
          if test $j = b; then
            continue 2
          fi
          echo $i$j >> #{output_file}
        done
        echo inner_done >> #{output_file}
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1a\n2a\n3a\n", File.read(output_file)
  end

  # Break/continue with conditionals
  def test_break_in_if_in_loop
    script = File.join(@tempdir, 'break_if.sh')
    File.write(script, <<~SCRIPT)
      for x in 1 2 3 4 5; do
        if test $x -eq 3; then
          break
        else
          echo $x >> #{output_file}
        fi
      done
    SCRIPT

    execute("source #{script}")
    assert_equal "1\n2\n", File.read(output_file)
  end

  # Simple inline break
  def test_simple_inline_break
    execute("for x in 1 2 3; do echo $x >> #{output_file}; if test $x -eq 2; then break; fi; done")
    assert_equal "1\n2\n", File.read(output_file)
  end

  # Simple inline continue
  def test_simple_inline_continue
    execute("for x in 1 2 3; do if test $x -eq 2; then continue; fi; echo $x >> #{output_file}; done")
    assert_equal "1\n3\n", File.read(output_file)
  end
end
