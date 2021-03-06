require 'active_record/typed_store/dsl'
require 'active_record/typed_store/type'
require 'active_record/typed_store/typed_hash'
require 'active_record/typed_store/identity_coder'

module ActiveRecord::TypedStore
  module Extension
    extend ActiveSupport::Concern

    included do
      class_attribute :typed_stores
      self.typed_stores = {}
    end

    module ClassMethods
      def store_accessors
        typed_stores.each_value.flat_map(&:accessors)
      end

      def typed_store(store_attribute, options={}, &block)
        dsl = DSL.new(store_attribute, options, &block)
        self.typed_stores = self.typed_stores.merge(store_attribute => dsl)

        typed_klass = TypedHash.create(dsl.fields.values)
        const_set("#{store_attribute}_hash".camelize, typed_klass)

        decorate_attribute_type(store_attribute, :typed_store) do |subtype|
          Type.new(typed_klass, dsl.coder, subtype)
        end
        store_accessor(store_attribute, dsl.accessors)

        dsl.accessors.each do |accessor_name|
          define_method("#{accessor_name}_changed?") do
            send("#{store_attribute}_changed?") &&
              send(store_attribute)[accessor_name] != send("#{store_attribute}_was")[accessor_name]
          end

          define_method("#{accessor_name}_was") do
            send("#{store_attribute}_was")[accessor_name]
          end

          define_method("restore_#{accessor_name}!") do
            send("#{accessor_name}=", send("#{accessor_name}_was"))
          end
        end
      end

      def define_attribute_methods
        super
        define_typed_store_attribute_methods
      end

      def undefine_attribute_methods # :nodoc:
        super if @typed_store_attribute_methods_generated
        @typed_store_attribute_methods_generated = false
      end

      def define_typed_store_attribute_methods
        return if @typed_store_attribute_methods_generated
        store_accessors.each do |attribute|
          define_attribute_method(attribute.to_s)
          undefine_before_type_cast_method(attribute)
        end
        @typed_store_attribute_methods_generated = true
      end

      def undefine_before_type_cast_method(attribute)
        # because it mess with ActionView forms, see #14.
        method = "#{attribute}_before_type_cast"
        undef_method(method) if method_defined?(method)
      end
    end

    def changes
      changes = super
      self.class.store_accessors.each do |attr|
        if send("#{attr}_changed?")
          changes[attr] = [send("#{attr}_was"), send(attr)]
        end
      end
      changes
    end

    def clear_attribute_change(attr_name)
      return if self.class.store_accessors.include?(normalize_attribute(attr_name))
      super
    end

    def read_attribute(attr_name)
      if self.class.store_accessors.include?(normalize_attribute(attr_name))
        return public_send(attr_name)
      end
      super
    end

    def query_attribute(attr_name)
      if self.class.store_accessors.include?(attr_name.to_sym)
        value = public_send(attr_name)

        case value
        when true        then true
        when false, nil  then false
        else
          if value.respond_to?(:zero?)
            !value.zero?
          else
            !value.blank?
          end
        end
      else
        super
      end
    end

    def normalize_attribute(attr)
      case attr
      when Symbol
        attr
      else
        attr.to_s.to_sym
      end
    end
  end
end
