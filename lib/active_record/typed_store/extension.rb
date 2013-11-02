require 'active_record/typed_store/column'
require 'active_record/typed_store/dsl'

module ActiveRecord::TypedStore
  AR_VERSION = Gem::Version.new(ActiveRecord::VERSION::STRING)
  IS_AR_3_2 = AR_VERSION < Gem::Version.new('4.0')
  IS_AR_4_0 = AR_VERSION >= Gem::Version.new('4.0') && AR_VERSION < Gem::Version.new('4.1.0.beta')
  IS_AR_4_1 = AR_VERSION >= Gem::Version.new('4.1.0.beta')

  module Extension
    extend ActiveSupport::Concern

    included do
      class_attribute :stored_typed_attributes, instance_accessor: false
      self.stored_typed_attributes = {}
    end

    module ClassMethods

      def typed_store(store_attribute, options={}, &block)
        dsl = DSL.new(&block)

        store(store_attribute, options.merge(accessors: dsl.column_names))

        stored_typed_attributes[store_attribute] ||= {}
        stored_typed_attributes[store_attribute].merge!(dsl.columns.index_by(&:name))

        if IS_AR_4_1 || IS_AR_3_2
          after_initialize { initialize_store_attribute(store_attribute) }
        end

        _ar_32_fallback_accessors(store_attribute, dsl.columns) if IS_AR_3_2
      end

      protected

      def _ar_32_fallback_accessors(store_attribute, columns)
        columns.each do |column|
          _ar_32_fallback_accessor(store_attribute, column)
        end
      end

      def _ar_32_fallback_accessor(store_attribute, column)
        define_method("#{column.name}_with_type_casting=") do |value|
          casted_value = column.type_cast(value)
          casted_value = column.default if casted_value.nil? && !column.null
          self.send("#{column.name}_without_type_casting=", casted_value)
        end
        alias_method_chain "#{column.name}=", :type_casting

        define_method(column.name) do
          send("#{store_attribute}=", {}) unless send(store_attribute).is_a?(Hash)
          store = send(store_attribute)
          store.has_key?(column.name) ? store[column.name] : column.default
        end
      end
      
    end

    protected

    def write_store_attribute(store_attribute, key, value)
      casted_value = value
      if store_definition = self.class.stored_typed_attributes[store_attribute]
        if column_definition = store_definition[key]
          casted_value = column_definition.type_cast(value)
          if !column_definition.null && (value.nil? || casted_value.nil?)
            casted_value = column_definition.default
          end
        end
      end
      super(store_attribute, key, casted_value)
    end

    private

    def initialize_store_attribute(store_attribute)
      store = IS_AR_4_0 ? super : send(store_attribute)
      if columns = self.class.stored_typed_attributes[store_attribute]
        store = initialize_store(store, columns)
      end
      store
    end

    def initialize_store(store, columns)
      columns.each do |name, definition|
        if store.has_key?(name)
          store[name] = definition.type_cast(store[name])
        else
          store[name] = definition.default if definition.has_default?
        end
      end
      store
    end

  end
end
