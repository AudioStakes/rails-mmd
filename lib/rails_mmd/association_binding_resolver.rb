# frozen_string_literal: true

require_relative 'key_tuple'

module RailsMmd
  # Normalizes Active Record association reflections into physical key bindings.
  module AssociationBindingResolver
    DIAGNOSTIC_CODE = 'ASSOCIATION_COMPOSITE_KEY_OMITTED'
    private_constant :DIAGNOSTIC_CODE

    Result = Struct.new(:binding, :diagnostic_code, keyword_init: true) do
      def success? = diagnostic_code.nil?
    end

    Binding = Struct.new(
      :foreign_key_columns,
      :referenced_key_columns,
      :foreign_type_column,
      keyword_init: true
    )

    module_function

    def belongs_to(reflection, target_model:)
      foreign_key_columns = KeyTuple.normalize(reflection.foreign_key)
      referenced_key_columns = KeyTuple.normalize(association_primary_key(reflection, target_model))
      polymorphic = reflection.polymorphic?
      foreign_type_column = scalar_column(reflection.foreign_type) if polymorphic

      result_for(foreign_key_columns, referenced_key_columns, foreign_type_column,
                 require_foreign_type: polymorphic)
    rescue LoadError, SyntaxError, StandardError
      failure
    end

    def has(reflection, owner_primary_key_columns:)
      foreign_key_columns = KeyTuple.normalize(reflection.foreign_key)
      referenced_value = reflection.active_record_primary_key
      referenced_value = owner_primary_key_columns if referenced_value.nil?
      referenced_key_columns = KeyTuple.normalize(referenced_value)
      polymorphic_inverse = reflection.options.key?(:as)
      foreign_type_column = scalar_column(reflection.type) if polymorphic_inverse

      result_for(foreign_key_columns, referenced_key_columns, foreign_type_column,
                 require_foreign_type: polymorphic_inverse)
    rescue LoadError, SyntaxError, StandardError
      failure
    end

    def polymorphic_root(reflection)
      foreign_key_columns = KeyTuple.normalize(reflection.foreign_key)
      foreign_type_column = scalar_column(reflection.foreign_type)
      return failure unless foreign_key_columns && foreign_type_column

      success(foreign_key_columns, nil, foreign_type_column)
    rescue LoadError, SyntaxError, StandardError
      failure
    end

    def association_primary_key(reflection, target_model)
      return reflection.association_primary_key if reflection.method(:association_primary_key).arity.zero?

      reflection.association_primary_key(target_model)
    end
    private_class_method :association_primary_key

    def scalar_column(value)
      value.dup.freeze if value.is_a?(String) && !value.empty?
    end
    private_class_method :scalar_column

    def result_for(foreign_key_columns, referenced_key_columns, foreign_type_column, require_foreign_type: false)
      return failure unless valid_pair?(foreign_key_columns, referenced_key_columns)
      return failure if require_foreign_type && foreign_type_column.nil?

      success(foreign_key_columns, referenced_key_columns, foreign_type_column)
    end
    private_class_method :result_for

    def valid_pair?(foreign_key_columns, referenced_key_columns)
      foreign_key_columns && referenced_key_columns &&
        foreign_key_columns.length == referenced_key_columns.length
    end
    private_class_method :valid_pair?

    def success(foreign_key_columns, referenced_key_columns, foreign_type_column)
      binding = Binding.new(
        foreign_key_columns: foreign_key_columns,
        referenced_key_columns: referenced_key_columns,
        foreign_type_column: foreign_type_column
      ).freeze
      Result.new(
        binding: binding,
        diagnostic_code: nil
      ).freeze
    end
    private_class_method :success

    def failure
      Result.new(binding: nil, diagnostic_code: DIAGNOSTIC_CODE).freeze
    end
    private_class_method :failure
  end
end
