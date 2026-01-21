# frozen_string_literal: true

require_relative 'test_helper'

class TestRequire < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_require_is_builtin
    assert Rubish::Builtins.builtin?('require')
  end

  def test_require_loads_library
    result = Rubish::Builtins.run('require', ['json'])
    assert result
    assert defined?(JSON)
  end

  def test_require_returns_false_for_nonexistent_library
    output = capture_output do
      result = Rubish::Builtins.run('require', ['nonexistent_library_xyz'])
      assert_false result
    end
    assert_match(/cannot load such file/, output)
  end

  def test_require_missing_operand
    output = capture_output do
      result = Rubish::Builtins.run('require', [])
      assert_false result
    end
    assert_match(/missing operand/, output)
  end

  def test_require_via_repl
    # Just verify it doesn't error - require returns true but REPL may not propagate it
    output = capture_output { execute('require json') }
    refute_match(/cannot load such file/, output)
  end
end
