# frozen_string_literal: true

# Polyfill Data.define for Ruby < 3.2
data_has_define = Data.respond_to?(:define)

unless data_has_define
  class Data
    def self.define(*keys, &block)
      # Use a module for initialize so that custom initialize can call super
      init_module = Module.new do
        define_method(:initialize) do |*args, **kwargs|
          # Ruby 2.6 has quirky keyword argument handling where a trailing Hash
          # may be interpreted as kwargs instead of a positional argument
          has_expected_kwargs = keys.any? { |k| kwargs.key?(k) }

          if has_expected_kwargs
            keys.each do |key|
              instance_variable_set("@#{key}", kwargs.fetch(key) { raise ArgumentError, "missing keyword: #{key}" })
            end
          elsif args.empty? && kwargs.empty?
            # Called from super with implicit kwargs (Ruby 2.x behavior)
            # Do nothing - instance variables already set by caller
          elsif args.size == 1 && args.first.is_a?(Hash)
            # Ruby 2.6 may pass keyword args as a positional hash
            hash = args.first
            keys.each do |key|
              instance_variable_set("@#{key}", hash.fetch(key) { raise ArgumentError, "missing keyword: #{key}" })
            end
          elsif kwargs.any? && args.size + 1 == keys.size
            # Ruby 2.6: trailing Hash was converted to kwargs, treat it as last positional arg
            all_args = args + [kwargs.to_h]
            keys.zip(all_args).each { |key, val| instance_variable_set("@#{key}", val) }
          elsif args.size == keys.size
            keys.zip(args).each { |key, val| instance_variable_set("@#{key}", val) }
          else
            raise ArgumentError, "wrong number of arguments (given #{args.size}, expected #{keys.size})"
          end
          freeze
        end
      end

      Class.new do
        include init_module

        keys.each do |key|
          define_method(key) { instance_variable_get("@#{key}") }
        end

        define_method(:deconstruct) { keys.map { |k| send(k) } }
        define_method(:deconstruct_keys) { |_| keys.to_h { |k| [k, send(k)] } }
        define_method(:to_h) { keys.to_h { |k| [k, send(k)] } }
        define_method(:members) { keys }

        define_method(:==) do |other|
          other.class == self.class && keys.all? { |k| send(k) == other.send(k) }
        end
        alias eql? ==

        define_method(:hash) { [self.class, *keys.map { |k| send(k) }].hash }

        class_exec(&block) if block
      end
    end
  end
end
