module MethodExtensions
  module MethodSuper
    # Returns method which will be called if given Method/UnboundMethod would
    # call `super`.
    # Implementation is incomplete with regard to modules included in singleton
    # class (`class C; extend M; end`), but such modules usually don't use `super`
    # anyway.
    #
    # Examples
    #
    #     class Base
    #       def meth; end
    #     end
    #
    #     class Derived < Base
    #       def meth; end
    #     end
    #
    #     ruby-1.9.2-head > Derived.instance_method(:meth)
    #      => #<UnboundMethod: Derived#meth>
    #
    #     ruby-1.9.2-head > Derived.instance_method(:meth).super
    #      => #<UnboundMethod: Base#meth>
    def super
      raise ArgumentError, "method doesn't have required @context_for_super instance variable set" unless @context_for_super

      klass, level, name = @context_for_super.values_at(:klass, :level, :name)

      unless @methods_all
        @methods_all = MethodSuper.methods_all(klass)

        # on first call ignore first found method
        superclass_index = MethodSuper.superclass_index(@methods_all,
                                                        level,
                                                        name)
        @methods_all = @methods_all[superclass_index + 1 .. -1]

      end

      superclass_index = MethodSuper.superclass_index(@methods_all,
                                                      level,
                                                      name)

      superclass = @methods_all[superclass_index].keys.first
      rest_methods_all = @methods_all[superclass_index + 1 .. -1]

      super_method = if level == :class && superclass.class == Class
        superclass.method(name)
      elsif level == :instance ||
              (level == :class && superclass.class == Module)
        superclass.instance_method(name)
      end

      super_method.instance_variable_set(:@context_for_super, @context_for_super)
      super_method.instance_variable_set(:@methods_all, rest_methods_all)
      super_method
    end

    private

    def self.superclass_index(methods_all, level, name)
      methods_all.index do |ancestor_with_methods|
        ancestor, methods =
                ancestor_with_methods.keys.first, ancestor_with_methods.values.first
        methods[level] && methods[level].any? do |level, methods|
          methods.include?(name)
        end
      end
    end

    def self.methods_all(klass)
      MethodSuper::Methods.new(klass, :ancestor_name_formatter => proc { |ancestor, _| ancestor }).all
    end

    class Methods
      def initialize(klass_or_module, options = {})
        @klass_or_module = klass_or_module
        @ancestor_name_formatter = options.fetch(:ancestor_name_formatter,
                                                 default_ancestor_name_formatter)
        @exclude_trite = options.fetch(:exclude_trite, true)
      end

      def all
        @all ||= find_all
      end

      VISIBILITIES = [ :public, :protected, :private ].freeze

      protected

      def default_ancestor_name_formatter
        proc do |ancestor, singleton|
          ancestor_name(ancestor, singleton)
        end
      end

      def find_all
        ancestors = [] # flattened ancestors (both normal and singleton)

        (@klass_or_module.ancestors - trite_ancestors).each do |ancestor|
          ancestor_singleton = ancestor.singleton_class

          # Modules don't inherit class methods from included modules
          unless @klass_or_module.instance_of?(Module) && ancestor != @klass_or_module
            class_methods = collect_instance_methods(ancestor_singleton)
          end

          instance_methods = collect_instance_methods(ancestor)

          append_ancestor_entry(ancestors, @ancestor_name_formatter[ancestor, false],
                                class_methods, instance_methods)

          (singleton_ancestors(ancestor) || []).each do |singleton_ancestor|
            class_methods = collect_instance_methods(singleton_ancestor)
            append_ancestor_entry(ancestors, @ancestor_name_formatter[singleton_ancestor, true],
                                  class_methods)
          end
        end

        ancestors
      end

      # singleton ancestors which ancestor introduced
      def singleton_ancestors(ancestor)
        @singleton_ancestors ||= all_singleton_ancestors
        @singleton_ancestors[ancestor]
      end

      def all_singleton_ancestors
        all = {}
        seen = []
        (@klass_or_module.ancestors - trite_ancestors).reverse.each do |ancestor|
          singleton_ancestors = ancestor.singleton_class.ancestors - trite_singleton_ancestors
          introduces = singleton_ancestors - seen
          all[ancestor] = introduces unless introduces.empty?
          seen.concat singleton_ancestors
        end
        all
      end

      def ancestor_name(ancestor, singleton)
        "#{ singleton ? "S" : ""}[#{ ancestor.is_a?(Class) ? "C" : "M" }] #{ ancestor.name || ancestor.to_s }"
      end

      # ancestor is included only when contributes some methods
      def append_ancestor_entry(ancestors, ancestor, class_methods, instance_methods = nil)
        if class_methods || instance_methods
          ancestor_entry = {}
          ancestor_entry[:class] = class_methods if class_methods
          ancestor_entry[:instance] = instance_methods if instance_methods
          ancestors << {ancestor => ancestor_entry}
        end
      end

      # Returns hash { :public => [...public methods...],
      #                :protected => [...private methods...],
      #                :private => [...private methods...] }
      # keys with empty values are excluded,
      # when no methods are found - returns nil
      def collect_instance_methods(klass)
        methods_with_visibility = VISIBILITIES.map do |visibility|
          methods = klass.send("#{ visibility }_instance_methods", false)
          [visibility, methods] unless methods.empty?
        end.compact
        Hash[methods_with_visibility] unless methods_with_visibility.empty?
      end

      def trite_singleton_ancestors
        return [] unless @exclude_trite
        @trite_singleton_ancestors ||= Class.new.singleton_class.ancestors
      end

      def trite_ancestors
        return [] unless @exclude_trite
        @trite_ancestors ||= Class.new.ancestors
      end
    end
  end

  class ::Method
    include MethodSuper
  end

  class ::UnboundMethod
    include MethodSuper
  end

  class ::Module
    def instance_method_with_ancestors_for_super(name)
      method = instance_method_without_ancestors_for_super(name)
      method.instance_variable_set(:@context_for_super,
                                   :klass => self,
                                   :level => :instance,
                                   :name => name)

      method
    end

    unless method_defined?(:instance_method_without_ancestors_for_super) ||
            private_method_defined?(:instance_method_without_ancestors_for_super)
      alias_method :instance_method_without_ancestors_for_super, :instance_method
      alias_method :instance_method, :instance_method_with_ancestors_for_super
    end
  end

  module ::Kernel
    def method_with_ancestors_for_super(name)
      method = method_without_ancestors_for_super(name)

      if respond_to?(:ancestors)
        method.instance_variable_set(:@context_for_super,
                                     :klass => self,
                                     :level => :class,
                                     :name => name)
      else
        method.instance_variable_set(:@context_for_super,
                                     :klass => self.class,
                                     :level => :instance,
                                     :name => name)
      end

      method
    end

    unless method_defined?(:method_without_ancestors_for_super) ||
            private_method_defined?(:method_without_ancestors_for_super)
      alias_method :method_without_ancestors_for_super, :method
      alias_method :method, :method_with_ancestors_for_super
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "rspec/core"
  require "rspec/expectations"
  require "rspec/matchers"

  module BaseIncludedModule
    def module_meth
    end
  end

  module BaseExtendedModule
    def module_meth
    end
  end

  class BaseClass
    include BaseIncludedModule
    extend BaseExtendedModule

    def self.singleton_meth
    end

    def meth
    end
  end

  class DerivedClass < BaseClass
    def self.singleton_meth
    end

    def self.module_meth
    end

    def meth
    end

    def module_meth
    end
  end

  describe Method do
    describe "#super" do
      context "when called on result of DerivedClass.method(:singleton_meth)" do
        it "returns BaseClass.method(:singleton_meth)" do
          DerivedClass.method(:singleton_meth).super.should == BaseClass.method(:singleton_meth)
        end

        context "chained .super calls" do
          context "when called on result of DerivedClass.method(:module_meth).super" do
            it "returns BaseModule.instance_method(:module_meth)" do
              DerivedClass.method(:module_meth).super.should == BaseExtendedModule.instance_method(:module_meth)
            end
          end

          context "with class methods coming from extended modules only" do
            it "returns proper super method" do
              m1 = Module.new do
                def m; end
              end
              m2 = Module.new do
                def m; end
              end
              c = Class.new do
                extend m1
                extend m2
              end
              c.method(:m).super.should == m1.instance_method(:m)
            end
          end
        end
      end

      context "when called on result of DerivedClass.new.method(:meth)" do
        it "returns BaseClass.instance_method(:meth)" do
          derived_instance = DerivedClass.new
          derived_instance.method(:meth).super.should == BaseClass.instance_method(:meth)
        end

        context "chained .super calls" do
          context "when called on result of DerivedClass.new.method(:module_meth).super" do
            it "returns BaseModule.instance_method(:module_meth)" do
              DerivedClass.new.method(:module_meth).super.should == BaseIncludedModule.instance_method(:module_meth) 
            end
          end
        end
      end

    end
  end

  describe UnboundMethod do
    describe "#super" do
      context "when called on result of DerivedClass.instance_method(:meth)" do
        it "returns BaseClass.instance_method(:meth)" do
          DerivedClass.instance_method(:meth).super.should == BaseClass.instance_method(:meth)
        end
      end
    end
  end
end
