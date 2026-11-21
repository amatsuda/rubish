# frozen_string_literal: true

module Rubish
  # A `name=(elements)` word given to declare, typeset, local or readonly.
  # It is a String holding the source form, so it travels through the
  # argument plumbing like any other word, and it carries the expanded
  # elements for the builtin to assign.
  class ArrayWord < String
    attr_reader :var_part, :values

    def initialize(var_part, values)
      super("#{var_part}(#{values.join(' ')})")
      @var_part = var_part
      @values = values
    end

    def name
      var_part.sub(/\+?=\z/, '')
    end

    def append?
      var_part.end_with?('+=')
    end
  end
end
