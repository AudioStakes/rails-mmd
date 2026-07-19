# frozen_string_literal: true

module RailsMmd
  # Resolves exact Ruby constants while containing ordinary autoload failures.
  # @api private
  class ConstantResolver
    def self.wrap(resolver)
      return resolver if resolver.is_a?(self)
      return new(loader: resolver.method(:resolve)) if resolver.respond_to?(:resolve)
      return new(loader: resolver) if resolver.respond_to?(:call)

      raise ArgumentError, 'constant resolver must respond to resolve or call'
    end

    def initialize(loader: method(:load_constant))
      @loader = loader
    end

    def resolve(name)
      loader.call(name)
    rescue ScriptError, StandardError
      nil
    end

    private

    attr_reader :loader

    def load_constant(name)
      name.split('::').reduce(Object) { |namespace, const_name| namespace.const_get(const_name, false) }
    end
  end
end
