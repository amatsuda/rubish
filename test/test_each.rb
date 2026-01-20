# frozen_string_literal: true

require_relative 'test_helper'

class TestEach < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_each_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Lexer tests
  def test_each_block_token
    tokens = Rubish::Lexer.new('ls.each {|x| echo $x }').tokenize
    # Should have WORD(ls), DOT, WORD(each), BLOCK
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls', tokens[0].value
    assert_equal :DOT, tokens[1].type
    assert_equal :WORD, tokens[2].type
    assert_equal 'each', tokens[2].value
    assert_equal :BLOCK, tokens[3].type
    assert_match(/\|x\|.*echo/, tokens[3].value)
  end

  # Parser tests - each is parsed as a command in a pipeline
  def test_each_simple_parsing
    tokens = Rubish::Lexer.new('ls.each {|x| echo $x }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'each', ast.commands[1].name
    assert_match(/\|x\|/, ast.commands[1].block)
  end

  def test_each_with_pipeline_parsing
    tokens = Rubish::Lexer.new('ls.grep(/foo/).each {|line| echo $line }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 3, ast.commands.length
    assert_equal 'each', ast.commands[2].name
  end

  # Codegen tests
  def test_each_codegen
    tokens = Rubish::Lexer.new('ls.each {|x| echo $x }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__each_loop/, code)
    assert_match(/__eval_shell_code/, code)
  end

  # Execution tests
  def test_each_iterates_over_lines
    # Test using printf as source (more portable than echo -e)
    execute("printf 'alpha\\nbeta\\ngamma\\n'.each {|x| echo \"got: $x\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/got: alpha/, content)
    assert_match(/got: beta/, content)
    assert_match(/got: gamma/, content)
  end

  def test_each_with_seq
    # Test using seq as source
    execute("seq(1, 3).each {|n| echo \"num: $n\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/num: 1/, content)
    assert_match(/num: 2/, content)
    assert_match(/num: 3/, content)
  end

  def test_each_with_ls
    # Create some test files
    File.write("#{@tempdir}/file1.txt", 'content1')
    File.write("#{@tempdir}/file2.txt", 'content2')

    # Use ls.each to iterate over files
    execute("ls(#{@tempdir}).each {|f| echo \"file: $f\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/file: file1\.txt/, content)
    assert_match(/file: file2\.txt/, content)
  end

  def test_each_with_pipeline_source
    # Create test file
    File.write("#{@tempdir}/data.txt", "foo\nbar\nfoo2\nbaz\n")

    # Use cat.grep as source (use string pattern, not regex literal for grep)
    execute("cat(#{@tempdir}/data.txt).grep(foo).each {|line| echo \"match: $line\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/match: foo/, content)
    assert_match(/match: foo2/, content)
    refute_match(/match: bar/, content)
    refute_match(/match: baz/, content)
  end

  # ==========================================================================
  # do...end block syntax tests
  # ==========================================================================

  def test_each_do_end_parsing
    tokens = Rubish::Lexer.new('ls | each do |x| echo $x end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 2, ast.commands.length
    assert_equal 'ls', ast.commands[0].name
    assert_equal 'each', ast.commands[1].name
    assert_match(/do.*\|x\|.*end/m, ast.commands[1].block)
  end

  def test_each_do_end_codegen
    tokens = Rubish::Lexer.new('ls | each do |x| echo $x end').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__each_loop/, code)
    assert_match(/"x"/, code)  # variable name extracted
  end

  def test_each_do_end_execution
    execute("seq 1 3 | each do |n| echo \"num: $n\" >> #{output_file} end")
    content = File.read(output_file)
    assert_match(/num: 1/, content)
    assert_match(/num: 2/, content)
    assert_match(/num: 3/, content)
  end

  def test_each_do_end_with_pipeline
    File.write("#{@tempdir}/data.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/data.txt | grep ap | each do |fruit| echo \"found: $fruit\" >> #{output_file} end")
    content = File.read(output_file)
    assert_match(/found: apple/, content)
    assert_match(/found: apricot/, content)
    refute_match(/found: banana/, content)
  end

  # ==========================================================================
  # Implicit $it variable tests
  # ==========================================================================

  def test_each_implicit_it_curly_brace
    execute("seq 1 3 | each { echo \"val: $it\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_do_end
    execute("seq 1 3 | each do echo \"val: $it\" >> #{output_file} end")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_method_chain
    execute("seq(1, 3).each { echo \"val: $it\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_lexer
    # Verify lexer produces BLOCK token for { body } after each
    tokens = Rubish::Lexer.new('ls | each { echo $it }').tokenize
    assert_equal :BLOCK, tokens.last.type
    assert_equal '{ echo $it }', tokens.last.value
  end

  def test_each_implicit_it_do_end_lexer
    # Verify lexer produces BLOCK token for do body end after each
    tokens = Rubish::Lexer.new('ls | each do echo $it end').tokenize
    assert_equal :BLOCK, tokens.last.type
    assert_match(/do.*end/, tokens.last.value)
  end

  # ==========================================================================
  # Map method tests
  # ==========================================================================

  def test_map_simple
    # map implicitly echoes the result of the block expression
    execute("seq 1 3 | map { $(($it * 2)) } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_map_with_explicit_variable
    execute("seq 1 3 | map {|n| $(($n + 10)) } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^11$/, content)
    assert_match(/^12$/, content)
    assert_match(/^13$/, content)
  end

  def test_map_method_chain
    execute("seq(1, 3).map { $(($it * 2)) } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_map_chained_with_each
    execute("seq(1, 3).map { $(($it * 2)) }.each { echo \"val: $it\" >> #{output_file} }")
    content = File.read(output_file)
    assert_match(/val: 2/, content)
    assert_match(/val: 4/, content)
    assert_match(/val: 6/, content)
  end

  def test_map_do_end_syntax
    execute("seq 1 3 | map do $(($it * 3)) end > #{output_file}")
    content = File.read(output_file)
    assert_match(/^3$/, content)
    assert_match(/^6$/, content)
    assert_match(/^9$/, content)
  end

  def test_map_lexer
    tokens = Rubish::Lexer.new('ls | map { $it }').tokenize
    assert_equal :BLOCK, tokens.last.type
  end

  def test_map_parsing
    tokens = Rubish::Lexer.new('seq 1 3 | map { $(($it * 2)) }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 'map', ast.commands.last.name
    # Block should contain the expression, not echo
    refute_match(/echo/, ast.commands.last.block)
  end

  # ==========================================================================
  # Select method tests (filtering)
  # ==========================================================================

  def test_select_simple
    # select filters lines where block condition is true
    execute("seq 1 6 | select { test $(($it % 2)) -eq 0 } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
    refute_match(/^1$/, content)
    refute_match(/^3$/, content)
    refute_match(/^5$/, content)
  end

  def test_select_with_explicit_variable
    execute("seq 1 6 | select {|n| test $(($n % 2)) -eq 0 } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_select_method_chain
    execute("seq(1, 6).select { test $(($it % 2)) -eq 0 } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_select_chained_with_map
    # Filter even numbers, then double them
    execute("seq(1, 6).select { test $(($it % 2)) -eq 0 }.map { $(($it * 2)) } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^4$/, content)   # 2 * 2
    assert_match(/^8$/, content)   # 4 * 2
    assert_match(/^12$/, content)  # 6 * 2
  end

  def test_select_do_end_syntax
    execute("seq 1 6 | select do test $(($it % 2)) -eq 0 end > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_select_with_grep_condition
    File.write("#{@tempdir}/data.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/data.txt | select { echo $it | grep -q ap } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^apple$/, content)
    assert_match(/^apricot$/, content)
    refute_match(/banana/, content)
    refute_match(/cherry/, content)
  end

  def test_select_lexer
    tokens = Rubish::Lexer.new('ls | select { test -f $it }').tokenize
    assert_equal :BLOCK, tokens.last.type
  end

  def test_select_parsing
    tokens = Rubish::Lexer.new('seq 1 10 | select { test $(($it % 2)) -eq 0 }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 'select', ast.commands.last.name
  end

  # ==========================================================================
  # Predicate method tests
  # ==========================================================================

  def test_empty_predicate_select
    # Create test file with empty lines
    File.write("#{@tempdir}/lines.txt", "a\n\nb\n\nc\n")
    execute("cat #{@tempdir}/lines.txt | select { $it.empty? } > #{output_file}")
    content = File.read(output_file)
    # Count newlines - each empty line selected produces one newline
    assert_equal 2, content.count("\n")  # Two empty lines
  end

  def test_empty_predicate_select_negated
    # Filter out empty lines
    File.write("#{@tempdir}/lines.txt", "a\n\nb\n\nc\n")
    execute("cat #{@tempdir}/lines.txt | select { ! $it.empty? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^a$/, content)
    assert_match(/^b$/, content)
    assert_match(/^c$/, content)
    lines = content.strip.split("\n")
    assert_equal 3, lines.length
  end

  def test_empty_predicate_with_explicit_variable
    File.write("#{@tempdir}/lines.txt", "x\n\ny\n")
    execute("cat #{@tempdir}/lines.txt | select {|line| ! $line.empty? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^x$/, content)
    assert_match(/^y$/, content)
    lines = content.strip.split("\n")
    assert_equal 2, lines.length
  end

  def test_empty_predicate_in_each
    # empty? can also be used in each blocks
    File.write("#{@tempdir}/lines.txt", "a\n\nb\n")
    execute("cat #{@tempdir}/lines.txt | each { if ! $it.empty?; then echo \"got: $it\"; fi } > #{output_file}")
    content = File.read(output_file)
    assert_match(/got: a/, content)
    assert_match(/got: b/, content)
    refute_match(/got: $/, content)  # No "got: " with empty value
  end

  def test_predicate_transform
    # Verify the transformation at codegen level
    codegen = Rubish::Codegen.new
    assert_equal 'test -z "$it"', codegen.send(:transform_predicates, '$it.empty?')
    assert_equal 'test -z "$foo"', codegen.send(:transform_predicates, '$foo.empty?')
    assert_equal '! test -z "$it"', codegen.send(:transform_predicates, '! $it.empty?')
    assert_equal 'test -n "$it"', codegen.send(:transform_predicates, '$it.any?')
    assert_equal 'test -n "$foo"', codegen.send(:transform_predicates, '$foo.any?')
  end

  def test_any_predicate_select
    # Select non-empty lines using any?
    File.write("#{@tempdir}/lines.txt", "a\n\nb\n\nc\n")
    execute("cat #{@tempdir}/lines.txt | select { $it.any? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^a$/, content)
    assert_match(/^b$/, content)
    assert_match(/^c$/, content)
    lines = content.strip.split("\n")
    assert_equal 3, lines.length
  end

  def test_any_predicate_with_explicit_variable
    File.write("#{@tempdir}/lines.txt", "x\n\ny\n")
    execute("cat #{@tempdir}/lines.txt | select {|line| $line.any? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^x$/, content)
    assert_match(/^y$/, content)
    lines = content.strip.split("\n")
    assert_equal 2, lines.length
  end

  def test_file_predicate_select
    # Create files and directories
    File.write("#{@tempdir}/file1.txt", 'content')
    File.write("#{@tempdir}/file2.txt", 'content')
    Dir.mkdir("#{@tempdir}/subdir")

    # List all entries and select only files
    execute("ls #{@tempdir} | each {|f| echo #{@tempdir}/$f } | select { $it.file? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
    refute_match(/subdir/, content)
  end

  def test_dir_predicate_select
    # Create files and directories
    File.write("#{@tempdir}/file1.txt", 'content')
    Dir.mkdir("#{@tempdir}/dir1")
    Dir.mkdir("#{@tempdir}/dir2")

    # List all entries and select only directories
    execute("ls #{@tempdir} | each {|f| echo #{@tempdir}/$f } | select { $it.dir? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/dir1/, content)
    assert_match(/dir2/, content)
    refute_match(/file1\.txt/, content)
  end

  def test_file_and_dir_predicate_transform
    codegen = Rubish::Codegen.new
    assert_equal 'test -f "$it"', codegen.send(:transform_predicates, '$it.file?')
    assert_equal 'test -d "$it"', codegen.send(:transform_predicates, '$it.dir?')
    assert_equal 'test -f "$path"', codegen.send(:transform_predicates, '$path.file?')
    assert_equal 'test -d "$path"', codegen.send(:transform_predicates, '$path.dir?')
  end
end
