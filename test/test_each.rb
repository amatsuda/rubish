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
    tokens = Rubish::Lexer.new('ls.each {|x| puts x }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    code = Rubish::Codegen.new.generate(ast)
    assert_match(/__each_loop/, code)
    assert_match(/puts x/, code)  # Ruby code is inlined directly
  end

  # Execution tests
  def test_each_iterates_over_lines
    # Test using printf as source (more portable than echo -e)
    execute("printf 'alpha\\nbeta\\ngamma\\n'.each {|x| File.write('#{output_file}', \"got: \#{x}\\n\", mode: 'a') }")
    content = File.read(output_file)
    assert_match(/got: alpha/, content)
    assert_match(/got: beta/, content)
    assert_match(/got: gamma/, content)
  end

  def test_each_with_seq
    # Test using seq as source
    execute("seq(1, 3).each {|n| File.write('#{output_file}', \"num: \#{n}\\n\", mode: 'a') }")
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
    execute("ls(#{@tempdir}).each {|f| File.write('#{output_file}', \"file: \#{f}\\n\", mode: 'a') }")
    content = File.read(output_file)
    assert_match(/file: file1\.txt/, content)
    assert_match(/file: file2\.txt/, content)
  end

  def test_each_with_pipeline_source
    # Create test file
    File.write("#{@tempdir}/data.txt", "foo\nbar\nfoo2\nbaz\n")

    # Use cat.grep as source (use string pattern, not regex literal for grep)
    execute("cat(#{@tempdir}/data.txt).grep(foo).each {|line| File.write('#{output_file}', \"match: \#{line}\\n\", mode: 'a') }")
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
    execute("seq 1 3 | each do |n| File.write('#{output_file}', \"num: \#{n}\\n\", mode: 'a') end")
    content = File.read(output_file)
    assert_match(/num: 1/, content)
    assert_match(/num: 2/, content)
    assert_match(/num: 3/, content)
  end

  def test_each_do_end_with_pipeline
    File.write("#{@tempdir}/data.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/data.txt | grep ap | each do |fruit| File.write('#{output_file}', \"found: \#{fruit}\\n\", mode: 'a') end")
    content = File.read(output_file)
    assert_match(/found: apple/, content)
    assert_match(/found: apricot/, content)
    refute_match(/found: banana/, content)
  end

  # ==========================================================================
  # Implicit it variable tests (Ruby's implicit block parameter)
  # ==========================================================================

  def test_each_implicit_it_curly_brace
    execute("seq 1 3 | each { File.write('#{output_file}', \"val: \#{it}\\n\", mode: 'a') }")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_do_end
    execute("seq 1 3 | each do File.write('#{output_file}', \"val: \#{it}\\n\", mode: 'a') end")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_method_chain
    execute("seq(1, 3).each { File.write('#{output_file}', \"val: \#{it}\\n\", mode: 'a') }")
    content = File.read(output_file)
    assert_match(/val: 1/, content)
    assert_match(/val: 2/, content)
    assert_match(/val: 3/, content)
  end

  def test_each_implicit_it_lexer
    # Verify lexer produces BLOCK token for { body } after each
    tokens = Rubish::Lexer.new('ls | each { puts it }').tokenize
    assert_equal :BLOCK, tokens.last.type
    assert_equal '{ puts it }', tokens.last.value
  end

  def test_each_implicit_it_do_end_lexer
    # Verify lexer produces BLOCK token for do body end after each
    tokens = Rubish::Lexer.new('ls | each do puts it end').tokenize
    assert_equal :BLOCK, tokens.last.type
    assert_match(/do.*end/, tokens.last.value)
  end

  # ==========================================================================
  # Map method tests (map evaluates block as Ruby)
  # ==========================================================================

  def test_map_simple
    # map evaluates block as Ruby and outputs result
    execute("seq 1 3 | map {|x| x.to_i * 2 } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_map_with_explicit_variable
    execute("seq 1 3 | map {|n| n.to_i + 10 } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^11$/, content)
    assert_match(/^12$/, content)
    assert_match(/^13$/, content)
  end

  def test_map_method_chain
    execute("seq(1, 3).map {|x| x.to_i * 2 } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_map_chained_with_each
    execute("seq(1, 3).map {|x| x.to_i * 2 }.each {|x| File.write('#{output_file}', \"val: \#{x}\\n\", mode: 'a') }")
    content = File.read(output_file)
    assert_match(/val: 2/, content)
    assert_match(/val: 4/, content)
    assert_match(/val: 6/, content)
  end

  def test_map_do_end_syntax
    execute("seq 1 3 | map do |x| x.to_i * 3 end > #{output_file}")
    content = File.read(output_file)
    assert_match(/^3$/, content)
    assert_match(/^6$/, content)
    assert_match(/^9$/, content)
  end

  def test_map_lexer
    tokens = Rubish::Lexer.new('ls | map {|x| x }').tokenize
    assert_equal :BLOCK, tokens.last.type
  end

  def test_map_parsing
    tokens = Rubish::Lexer.new('seq 1 3 | map {|x| x.to_i * 2 }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 'map', ast.commands.last.name
  end

  # ==========================================================================
  # Select method tests (select evaluates block as Ruby)
  # ==========================================================================

  def test_select_simple
    # select evaluates block as Ruby, outputs line if truthy
    execute("seq 1 6 | select {|x| x.to_i.even? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
    refute_match(/^1$/, content)
    refute_match(/^3$/, content)
    refute_match(/^5$/, content)
  end

  def test_select_with_explicit_variable
    execute("seq 1 6 | select {|n| n.to_i.even? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_select_method_chain
    execute("seq(1, 6).select {|x| x.to_i.even? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_select_chained_with_map
    # Filter even numbers, then double them
    execute("seq(1, 6).select {|x| x.to_i.even? }.map {|x| x.to_i * 2 } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^4$/, content)   # 2 * 2
    assert_match(/^8$/, content)   # 4 * 2
    assert_match(/^12$/, content)  # 6 * 2
  end

  def test_select_do_end_syntax
    execute("seq 1 6 | select do |x| x.to_i.even? end > #{output_file}")
    content = File.read(output_file)
    assert_match(/^2$/, content)
    assert_match(/^4$/, content)
    assert_match(/^6$/, content)
  end

  def test_select_with_include_condition
    File.write("#{@tempdir}/data.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/data.txt | select {|x| x.include?(\"ap\") } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^apple$/, content)
    assert_match(/^apricot$/, content)
    refute_match(/banana/, content)
    refute_match(/cherry/, content)
  end

  def test_select_lexer
    tokens = Rubish::Lexer.new('ls | select {|x| File.file?(x) }').tokenize
    assert_equal :BLOCK, tokens.last.type
  end

  def test_select_parsing
    tokens = Rubish::Lexer.new('seq 1 10 | select {|x| x.to_i.even? }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::Pipeline, ast
    assert_equal 'select', ast.commands.last.name
  end

  # ==========================================================================
  # Ruby block evaluation tests (select/map use Ruby, each uses shell)
  # ==========================================================================

  def test_select_with_ruby_empty
    # select evaluates block as Ruby - use String#empty?
    File.write("#{@tempdir}/lines.txt", "a\n\nb\n\nc\n")
    execute("cat #{@tempdir}/lines.txt | select {|x| x.empty? } > #{output_file}")
    content = File.read(output_file)
    assert_equal 2, content.count("\n")  # Two empty lines
  end

  def test_select_with_ruby_not_empty
    # Filter out empty lines using Ruby
    File.write("#{@tempdir}/lines.txt", "a\n\nb\n\nc\n")
    execute("cat #{@tempdir}/lines.txt | select {|x| !x.empty? } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^a$/, content)
    assert_match(/^b$/, content)
    assert_match(/^c$/, content)
    lines = content.strip.split("\n")
    assert_equal 3, lines.length
  end

  def test_select_with_ruby_equality
    # Select specific value with Ruby ==
    execute('seq 1 5 | select {|x| x == "3" } > ' + output_file)
    content = File.read(output_file).strip
    assert_equal '3', content
  end

  def test_select_with_ruby_inequality
    # Select values not equal to 3
    execute('seq 1 5 | select {|x| x != "3" } > ' + output_file)
    content = File.read(output_file).strip
    lines = content.split("\n")
    assert_equal 4, lines.length
    refute_includes lines, '3'
  end

  def test_select_with_ruby_include
    # Use Ruby's include? method
    File.write("#{@tempdir}/words.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/words.txt | select {|x| x.include?(\"ap\") } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^apple$/, content)
    assert_match(/^apricot$/, content)
    refute_match(/banana/, content)
    refute_match(/cherry/, content)
  end

  def test_select_with_ruby_start_with
    # Use Ruby's start_with? method
    File.write("#{@tempdir}/words.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/words.txt | select {|x| x.start_with?(\"a\") } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^apple$/, content)
    assert_match(/^apricot$/, content)
    refute_match(/banana/, content)
  end

  def test_select_with_ruby_match
    # Use Ruby's match? for regex
    File.write("#{@tempdir}/words.txt", "apple\nbanana\napricot\ncherry\n")
    execute("cat #{@tempdir}/words.txt | select {|x| x.match?(/^a/) } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^apple$/, content)
    assert_match(/^apricot$/, content)
    refute_match(/banana/, content)
  end

  def test_select_with_ruby_numeric
    # Use Ruby numeric comparison (convert to int)
    execute('seq 1 10 | select {|x| x.to_i > 5 } > ' + output_file)
    content = File.read(output_file).strip
    lines = content.split("\n")
    assert_equal 5, lines.length
    assert_equal %w[6 7 8 9 10], lines
  end

  def test_select_with_ruby_even
    # Use Ruby's even? method
    execute('seq 1 10 | select {|x| x.to_i.even? } > ' + output_file)
    content = File.read(output_file).strip
    lines = content.split("\n")
    assert_equal %w[2 4 6 8 10], lines
  end

  def test_select_with_file_exist
    # Use Ruby's File.file?
    File.write("#{@tempdir}/file1.txt", 'content')
    File.write("#{@tempdir}/file2.txt", 'content')
    Dir.mkdir("#{@tempdir}/subdir")

    execute("ls #{@tempdir} | map {|f| '#{@tempdir}/' + f } | select {|x| File.file?(x) } > #{output_file}")
    content = File.read(output_file)
    assert_match(/file1\.txt/, content)
    assert_match(/file2\.txt/, content)
    refute_match(/subdir/, content)
  end

  def test_select_with_directory
    # Use Ruby's File.directory?
    File.write("#{@tempdir}/file1.txt", 'content')
    Dir.mkdir("#{@tempdir}/dir1")
    Dir.mkdir("#{@tempdir}/dir2")

    execute("ls #{@tempdir} | map {|f| '#{@tempdir}/' + f } | select {|x| File.directory?(x) } > #{output_file}")
    content = File.read(output_file)
    assert_match(/dir1/, content)
    assert_match(/dir2/, content)
    refute_match(/file1\.txt/, content)
  end

  def test_map_with_ruby_upcase
    # map evaluates block as Ruby and outputs result
    File.write("#{@tempdir}/words.txt", "hello\nworld\n")
    execute("cat #{@tempdir}/words.txt | map {|x| x.upcase } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^HELLO$/, content)
    assert_match(/^WORLD$/, content)
  end

  def test_map_with_ruby_arithmetic
    # map with arithmetic
    execute('seq 1 3 | map {|x| x.to_i * 2 } > ' + output_file)
    content = File.read(output_file).strip
    lines = content.split("\n")
    assert_equal %w[2 4 6], lines
  end

  def test_map_with_ruby_string_manipulation
    # map with string manipulation
    File.write("#{@tempdir}/words.txt", "  hello  \n  world  \n")
    execute("cat #{@tempdir}/words.txt | map {|x| x.strip } > #{output_file}")
    content = File.read(output_file)
    assert_match(/^hello$/, content)
    assert_match(/^world$/, content)
  end

  def test_each_uses_ruby
    # each evaluates block as Ruby code - can use echo builtin
    File.write("#{@tempdir}/lines.txt", "a\nb\nc\n")
    execute("cat #{@tempdir}/lines.txt | each {|x| echo \"got: \#{x}\" } > #{output_file}")
    content = File.read(output_file)
    assert_match(/got: a/, content)
    assert_match(/got: b/, content)
    assert_match(/got: c/, content)
  end
end
