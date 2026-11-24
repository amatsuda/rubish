# frozen_string_literal: true

module Rubish
  # Evaluates shell arithmetic — $(( )), (( )), let, declare -i, array
  # subscripts — with bash semantics, without ever handing the text to
  # Ruby's eval. Variable values are themselves parsed as arithmetic (as in
  # bash), so a value like `system("rm -rf ~")` is a syntax error, not code.
  #
  # Integers are 64-bit two's complement. A literal with a decimal point, or
  # a float-valued math function, switches that computation to floating
  # point (zsh behaviour, relied on by prompts doing EPOCHREALTIME maths).
  #
  # The evaluator talks to the shell only through the callbacks given to
  # #initialize, which keeps it unit-testable and free of global state.
  class ArithmeticEvaluator
    class Error < StandardError; end

    INT_MIN = -(2**63)
    INT_MAX = 2**63 - 1
    UINT_MOD = 2**64
    MAX_RECURSION = 128

    FUNCTIONS = {
      'int' => ->(x) { x.to_i },
      'float' => ->(x) { x.to_f },
      'rint' => ->(x) { x.round },
      'floor' => ->(x) { x.floor },
      'ceil' => ->(x) { x.ceil },
      'abs' => ->(x) { x.abs },
      'sqrt' => ->(x) { Math.sqrt(x) },
      'exp' => ->(x) { Math.exp(x) },
      'log' => ->(x) { Math.log(x) },
      'log2' => ->(x) { Math.log2(x) },
      'log10' => ->(x) { Math.log10(x) },
      'sin' => ->(x) { Math.sin(x) },
      'cos' => ->(x) { Math.cos(x) },
      'tan' => ->(x) { Math.tan(x) },
      'asin' => ->(x) { Math.asin(x) },
      'acos' => ->(x) { Math.acos(x) },
      'atan' => ->(x) { Math.atan(x) },
      'atan2' => ->(y, x) { Math.atan2(y, x) }
    }.freeze

    # Longest operators first so the tokenizer matches greedily
    OPERATORS = %w[
      **= <<= >>= ** << >> <= >= == != && || ++ -- += -= *= /= %= &= |= ^=
      + - * / % < > = ! ~ & | ^ ? : , ( ) [ ]
    ].freeze

    ASSIGNMENT_OPERATORS = %w[= += -= *= /= %= **= <<= >>= &= |= ^=].freeze

    Token = Struct.new(:type, :value, :text)

    # get_var:            ->(name) { String or nil }
    # set_var:            ->(name, value_string) { }
    # get_array_element:  ->(name, index) { String or nil }
    # set_array_element:  ->(name, index, value_string) { }
    # positional:         ->(n) { String or nil }        ($1, $2, …)
    # var_set:            ->(name) { true/false }        (${+name}, zsh)
    # subst:              ->(command) { output String }  ($(cmd) inside the expression)
    def initialize(get_var:, set_var:, get_array_element: nil, set_array_element: nil,
                   positional: nil, var_set: nil, subst: nil)
      @get_var = get_var
      @set_var = set_var
      @get_array_element = get_array_element || ->(_name, _index) { nil }
      @set_array_element = set_array_element || ->(_name, _index, _value) {}
      @positional = positional || ->(_n) { nil }
      @tokens = @pos = @source = nil
      @var_set = var_set || ->(name) { !@get_var.call(name).nil? }
      @subst = subst
      @depth = 0
      @dry = 0
    end

    # Returns an Integer, or a Float when floating point was involved.
    def evaluate(expr)
      saved = [@tokens, @pos, @source]
      # Double quotes undergo quote removal before evaluation, as in bash:
      # $(( "1" + 1 )) is 2. Single quotes stay and are an error, as in bash.
      @source = expr.to_s.gsub(/"((?:[^"\\]|\\.)*)"/) { $1 }
      @tokens = tokenize(@source)
      @pos = 0
      return 0 if peek.type == :eof

      value = parse_comma
      error("arithmetic syntax error: unexpected token \"#{peek.text}\"") unless peek.type == :eof
      value
    ensure
      @tokens, @pos, @source = saved
    end

    private

    # ------------------------------------------------------------------
    # Tokenizer
    # ------------------------------------------------------------------

    def tokenize(src)
      tokens = []
      i = 0
      len = src.length
      while i < len
        c = src[i]
        if c =~ /\s/
          i += 1
        elsif c =~ /[0-9]/ || (c == '.' && src[i + 1] =~ /[0-9]/)
          j = i
          j += 1 while j < len && src[j] =~ /[0-9a-zA-Z#._@]/
          text = src[i...j]
          tokens << Token.new(:num, parse_number(text), text)
          i = j
        elsif c =~ /[a-zA-Z_]/
          j = i
          j += 1 while j < len && src[j] =~ /[a-zA-Z0-9_]/
          tokens << Token.new(:ident, src[i...j], src[i...j])
          i = j
        elsif c == '$'
          tok, i = tokenize_dollar(src, i)
          tokens << tok
        elsif (op = OPERATORS.find { |o| src[i, o.length] == o })
          tokens << Token.new(:op, op, op)
          i += op.length
        else
          error("arithmetic syntax error: invalid arithmetic operator (error token is \"#{src[i..]}\")")
        end
      end
      tokens << Token.new(:eof, nil, '')
    end

    def tokenize_dollar(src, i)
      nxt = src[i + 1]
      if nxt == '(' && src[i + 2] == '('
        close = matching_close(src, i + 2, '(', ')')
        error('arithmetic syntax error: unterminated $((') unless close && src[close + 1] == ')'
        [Token.new(:arith, src[(i + 3)...close], src[i..(close + 1)]), close + 2]
      elsif nxt == '('
        close = matching_close(src, i + 1, '(', ')')
        error('arithmetic syntax error: unterminated $(') unless close
        [Token.new(:subst, src[(i + 2)...close], src[i..close]), close + 1]
      elsif nxt == '{'
        close = matching_close(src, i + 1, '{', '}')
        error('arithmetic syntax error: unterminated ${') unless close
        [Token.new(:braced, src[(i + 2)...close], src[i..close]), close + 1]
      elsif nxt =~ /[0-9]/
        j = i + 1
        j += 1 while j < src.length && src[j] =~ /[0-9]/
        [Token.new(:positional, src[(i + 1)...j].to_i, src[i...j]), j]
      elsif nxt =~ /[a-zA-Z_]/
        j = i + 1
        j += 1 while j < src.length && src[j] =~ /[a-zA-Z0-9_]/
        [Token.new(:dollar_ident, src[(i + 1)...j], src[i...j]), j]
      else
        error("arithmetic syntax error: operand expected (error token is \"#{src[i..]}\")")
      end
    end

    def matching_close(src, open_pos, open, close)
      depth = 0
      (open_pos...src.length).each do |k|
        depth += 1 if src[k] == open
        depth -= 1 if src[k] == close
        return k if depth == 0
      end
      nil
    end

    def parse_number(text)
      if text =~ /\A0[xX]([0-9a-fA-F]+)\z/
        $1.to_i(16)
      elsif text =~ /\A([0-9]+)#([0-9a-zA-Z@_]+)\z/
        parse_based_number($1.to_i, $2, text)
      elsif text =~ /\A(?:[0-9]+\.[0-9]*|\.[0-9]+)\z/
        text.to_f
      elsif text =~ /\A0[0-7]*\z/
        text.to_i(8)
      elsif text =~ /\A0[0-9]+\z/
        error("value too great for base (error token is \"#{text}\")")
      elsif text =~ /\A[0-9]+\z/
        text.to_i
      else
        error("arithmetic syntax error: invalid number (error token is \"#{text}\")")
      end
    end

    def parse_based_number(base, digits, text)
      error("invalid arithmetic base (error token is \"#{text}\")") unless (2..64).cover?(base)
      digits.each_char.reduce(0) do |acc, ch|
        value = case ch
                when '0'..'9' then ch.ord - '0'.ord
                when 'a'..'z' then ch.ord - 'a'.ord + 10
                when 'A'..'Z' then base <= 36 ? ch.ord - 'A'.ord + 10 : ch.ord - 'A'.ord + 36
                when '@' then 62
                when '_' then 63
                end
        error("value too great for base (error token is \"#{text}\")") if value >= base
        acc * base + value
      end
    end

    # ------------------------------------------------------------------
    # Parser (C precedence, lowest first)
    # ------------------------------------------------------------------

    def peek(offset = 0)
      @tokens[@pos + offset] || @tokens.last
    end

    def advance
      tok = @tokens[@pos]
      @pos += 1
      tok
    end

    def accept(op)
      return nil unless peek.type == :op && peek.value == op

      advance
    end

    def expect(op)
      accept(op) || error("arithmetic syntax error: expected \"#{op}\" (error token is \"#{peek.text}\")")
    end

    def parse_comma
      value = parse_assign
      value = parse_assign while accept(',')
      value
    end

    def parse_assign
      start = @pos
      lvalue = try_parse_lvalue
      if lvalue && peek.type == :op && ASSIGNMENT_OPERATORS.include?(peek.value)
        op = advance.value
        rhs = parse_assign
        value = op == '=' ? rhs : binary(op[0...-1], read_lvalue(lvalue), rhs)
        write_lvalue(lvalue, value)
        return value
      end
      @pos = start
      parse_ternary
    end

    # [:var, name] or [:elem, name, index]; nil (position restored) if the
    # tokens here are not an lvalue
    def try_parse_lvalue
      return nil unless peek.type == :ident

      start = @pos
      name = advance.value
      if accept('[')
        index = parse_comma
        expect(']')
        return [:elem, name, index.to_i]
      end
      return [:var, name] unless peek.type == :op && peek.value == '('

      @pos = start
      nil
    end

    def parse_ternary
      cond = parse_lor
      return cond unless accept('?')

      if truthy?(cond)
        value = parse_assign
        expect(':')
        dry { parse_assign }
        value
      else
        dry { parse_assign }
        expect(':')
        parse_assign
      end
    end

    def parse_lor
      left = parse_land
      while accept('||')
        if truthy?(left)
          dry { parse_land }
          left = 1
        else
          left = truthy?(parse_land) ? 1 : 0
        end
      end
      left
    end

    def parse_land
      left = parse_bor
      while accept('&&')
        if truthy?(left)
          left = truthy?(parse_bor) ? 1 : 0
        else
          dry { parse_bor }
          left = 0
        end
      end
      left
    end

    def parse_bor
      left = parse_bxor
      left = binary('|', left, parse_bxor) while accept('|')
      left
    end

    def parse_bxor
      left = parse_band
      left = binary('^', left, parse_band) while accept('^')
      left
    end

    def parse_band
      left = parse_equality
      left = binary('&', left, parse_equality) while accept('&')
      left
    end

    def parse_equality
      left = parse_relational
      while (op = accept('==') || accept('!='))
        left = binary(op.value, left, parse_relational)
      end
      left
    end

    def parse_relational
      left = parse_shift
      while (op = accept('<=') || accept('>=') || accept('<') || accept('>'))
        left = binary(op.value, left, parse_shift)
      end
      left
    end

    def parse_shift
      left = parse_additive
      while (op = accept('<<') || accept('>>'))
        left = binary(op.value, left, parse_additive)
      end
      left
    end

    def parse_additive
      left = parse_multiplicative
      while (op = accept('+') || accept('-'))
        left = binary(op.value, left, parse_multiplicative)
      end
      left
    end

    def parse_multiplicative
      left = parse_power
      while (op = accept('*') || accept('/') || accept('%'))
        left = binary(op.value, left, parse_power)
      end
      left
    end

    # Right associative; unary minus binds tighter (bash: -2**2 == 4)
    def parse_power
      base = parse_unary
      return base unless accept('**')

      binary('**', base, parse_power)
    end

    def parse_unary
      if accept('-')
        wrap(-parse_unary)
      elsif accept('+')
        parse_unary
      elsif accept('!')
        truthy?(parse_unary) ? 0 : 1
      elsif accept('~')
        wrap(~parse_unary.to_i)
      elsif (op = accept('++') || accept('--'))
        lvalue = try_parse_lvalue || error('arithmetic syntax error: operand expected after ' + op.value)
        value = binary(op.value[0], read_lvalue(lvalue), 1)
        write_lvalue(lvalue, value)
        value
      else
        parse_postfix
      end
    end

    def parse_postfix
      value, lvalue = parse_primary
      if lvalue && (op = accept('++') || accept('--'))
        write_lvalue(lvalue, binary(op.value[0], value, 1))
      end
      value
    end

    # Returns [value, lvalue-or-nil]
    def parse_primary
      tok = peek
      case tok.type
      when :num
        advance
        [tok.value, nil]
      when :ident
        parse_identifier
      when :dollar_ident
        advance
        if accept('[') # zsh-style $arr[expr]
          index = parse_comma
          expect(']')
          [to_value(@get_array_element.call(tok.value, index.to_i)), nil]
        else
          [variable_value(tok.value), nil]
        end
      when :positional
        advance
        [to_value(@positional.call(tok.value)), nil]
      when :braced
        advance
        [braced_value(tok.value), nil]
      when :subst
        advance
        [@dry > 0 || @subst.nil? ? 0 : to_value(@subst.call(tok.value)), nil]
      when :arith
        advance
        [evaluate(tok.value), nil]
      when :op
        if accept('(')
          value = parse_comma
          expect(')')
          [value, nil]
        else
          error("arithmetic syntax error: operand expected (error token is \"#{tok.text}\")")
        end
      else
        error('arithmetic syntax error: operand expected')
      end
    end

    def parse_identifier
      name = advance.value
      if accept('(')
        fn = FUNCTIONS[name] || error("unknown function: #{name}")
        args = []
        unless accept(')')
          args << parse_assign
          args << parse_assign while accept(',')
          expect(')')
        end
        error("#{name}: wrong number of arguments") unless args.length == fn.arity
        [fn.call(*args), nil]
      elsif accept('[')
        index = parse_comma
        expect(']')
        lvalue = [:elem, name, index.to_i]
        [read_lvalue(lvalue), lvalue]
      else
        lvalue = [:var, name]
        [read_lvalue(lvalue), lvalue]
      end
    end

    # ------------------------------------------------------------------
    # Values, variables
    # ------------------------------------------------------------------

    def braced_value(content)
      if content =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[(.+)\]\z/
        to_value(@get_array_element.call($1, evaluate($2).to_i))
      elsif content =~ /\A\+([a-zA-Z_][a-zA-Z0-9_]*)\z/
        @var_set.call($1) ? 1 : 0
      elsif content =~ /\A#([a-zA-Z_][a-zA-Z0-9_]*)\z/
        @get_var.call($1).to_s.length
      elsif content =~ /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
        variable_value(content)
      elsif content =~ /\A[0-9]+\z/
        to_value(@positional.call(content.to_i))
      else
        error("arithmetic syntax error: unsupported expansion \"${#{content}}\"")
      end
    end

    def read_lvalue(lvalue)
      case lvalue[0]
      when :var then variable_value(lvalue[1])
      when :elem then to_value(@get_array_element.call(lvalue[1], lvalue[2]))
      end
    end

    def write_lvalue(lvalue, value)
      return value if @dry > 0

      # Shell variables hold integers; floats only live inside an expression
      text = value.to_i.to_s
      case lvalue[0]
      when :var then @set_var.call(lvalue[1], text)
      when :elem then @set_array_element.call(lvalue[1], lvalue[2], text)
      end
      value
    end

    def variable_value(name)
      to_value(@get_var.call(name))
    end

    # A variable's text is a number, or (as in bash) another expression
    def to_value(raw)
      text = raw.to_s.strip
      return 0 if text.empty?
      # A leading 0 makes the value octal, as for a literal (bash)
      return Integer(text, 8) if text.match?(/\A-?0[0-7]+\z/)
      error("value too great for base (error token is \"#{text}\")") if text.match?(/\A-?0[0-9]+\z/)
      return text.to_i if text.match?(/\A-?[0-9]+\z/)
      return text.to_f if text.match?(/\A-?[0-9]+\.[0-9]+\z/)

      error('expression recursion level exceeded') if @depth >= MAX_RECURSION
      @depth += 1
      begin
        evaluate(text)
      ensure
        @depth -= 1
      end
    end

    # ------------------------------------------------------------------
    # Operators
    # ------------------------------------------------------------------

    def truthy?(value)
      value != 0
    end

    def dry
      @dry += 1
      yield
    ensure
      @dry -= 1
    end

    def binary(op, a, b)
      case op
      when '+' then wrap(a + b)
      when '-' then wrap(a - b)
      when '*' then wrap(a * b)
      when '/' then divide(a, b)
      when '%' then modulo(a, b)
      when '**' then power(a, b)
      when '<<' then wrap(a.to_i << (b.to_i & 63))
      when '>>' then wrap(a.to_i >> (b.to_i & 63))
      when '&' then wrap(a.to_i & b.to_i)
      when '|' then wrap(a.to_i | b.to_i)
      when '^' then wrap(a.to_i ^ b.to_i)
      when '<' then a < b ? 1 : 0
      when '>' then a > b ? 1 : 0
      when '<=' then a <= b ? 1 : 0
      when '>=' then a >= b ? 1 : 0
      when '==' then a == b ? 1 : 0
      when '!=' then a != b ? 1 : 0
      else error("unknown operator #{op}")
      end
    end

    def divide(a, b)
      if b == 0
        return 0 if @dry > 0

        error('division by 0')
      end
      return a.to_f / b if a.is_a?(Float) || b.is_a?(Float)

      # C semantics: truncate toward zero
      quotient = a.abs / b.abs
      wrap((a < 0) ^ (b < 0) ? -quotient : quotient)
    end

    def modulo(a, b)
      if b == 0
        return 0 if @dry > 0

        error('division by 0')
      end
      return a.to_f.remainder(b) if a.is_a?(Float) || b.is_a?(Float)

      wrap(a.remainder(b))
    end

    def power(a, b)
      if a.is_a?(Float) || b.is_a?(Float)
        a**b
      elsif b < 0
        return 0 if @dry > 0

        error('exponent less than 0')
      else
        wrap(a.pow(b, UINT_MOD))
      end
    end

    # 64-bit two's complement wraparound for integers; floats pass through
    def wrap(value)
      return value unless value.is_a?(Integer)
      return value if value.between?(INT_MIN, INT_MAX)

      ((value - INT_MIN) % UINT_MOD) + INT_MIN
    end

    def error(message)
      raise Error, "#{@source.lstrip}: #{message}" # bash shows the expression without its leading whitespace
    end
  end
end
