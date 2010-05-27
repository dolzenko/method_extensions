ripper_available = true
begin
  require "ripper"
rescue LoadError
  ripper_available = false
end

module MethodSourceWithDoc
  # Returns method source by parsing the file returned by `Method#source_location`.
  #
  # If method definition cannot be found `ArgumentError` exception is raised
  # (this includes methods defined `attr_accessor`, `module_eval` etc.).
  #
  # Sample IRB session:
  #
  #     ruby-1.9.2-head > require 'fileutils'
  #
  #     ruby-1.9.2-head > puts FileUtils.method(:mkdir).source
  #     def mkdir(list, options = {})
  #         fu_check_options options, OPT_TABLE['mkdir']
  #         list = fu_list(list)
  #         fu_output_message "mkdir #{options[:mode] ? ('-m %03o ' % options[:mode]) : ''}#{list.join ' '}" if options[:verbose]
  #         return if options[:noop]
  #
  #         list.each do |dir|
  #           fu_mkdir dir, options[:mode]
  #         end
  #       end
  #      => nil
  def source
    MethodSourceRipper.source_from_source_location(source_location)
  end

  # Returns comment preceding the method definition by parsing the file
  # returned by `Method#source_location`
  #
  # Sample IRB session:
  #
  #     ruby-1.9.2-head > require 'fileutils'
  #
  #     ruby-1.9.2-head > puts FileUtils.method(:mkdir).doc
  #     #
  #     # Options: mode noop verbose
  #     #
  #     # Creates one or more directories.
  #     #
  #     #   FileUtils.mkdir 'test'
  #     #   FileUtils.mkdir %w( tmp data )
  #     #   FileUtils.mkdir 'notexist', :noop => true  # Does not really create.
  #     #   FileUtils.mkdir 'tmp', :mode => 0700
  #     #
  def doc
    MethodDocRipper.doc_from_source_location(source_location)
  end

  # ruby-1.9.2-head > irb_context.inspect_mode = false # turn off inspect mode so that we can view sources
  #
  # ruby-1.9.2-head > ActiveRecord::Base.method(:find).source_with_doc
  # ArgumentError: failed to find method definition around the lines:
  #       delegate :find, :first, :last, :all, :destroy, :destroy_all, :exists?, :delete, :delete_all, :update, :update_all, :to => :scoped
  #       delegate :find_each, :find_in_batches, :to => :scoped
  #
  # ruby-1.9.2-head > ActiveRecord::Base.method(:scoped).source_with_doc
  #  # Returns an anonymous scope.
  #  #
  #  #   posts = Post.scoped
  #  #   posts.size # Fires "select count(*) from  posts" and returns the count
  #  #   posts.each {|p| puts p.name } # Fires "select * from posts" and loads post objects
  #  #
  #  #   fruits = Fruit.scoped
  #  #   fruits = fruits.where(:colour => 'red') if options[:red_only]
  #  #   fruits = fruits.limit(10) if limited?
  #  #
  #  # Anonymous \scopes tend to be useful when procedurally generating complex queries, where passing
  #  # intermediate values (scopes) around as first-class objects is convenient.
  #  #
  #  # You can define a scope that applies to all finders using ActiveRecord::Base.default_scope.
  #  def scoped(options = {}, &block)
  #    if options.present?
  #      relation = scoped.apply_finder_options(options)
  #      block_given? ? relation.extending(Module.new(&block)) : relation
  #    else
  #      current_scoped_methods ? unscoped.merge(current_scoped_methods) : unscoped.clone
  #    end
  #  end
  #
  #  ruby-1.9.2-head > ActiveRecord::Base.method(:unscoped).source_with_doc
  #   => def unscoped
  #    @unscoped ||= Relation.new(self, arel_table)
  #    finder_needs_type_condition? ? @unscoped.where(type_condition) : @unscoped
  #  end
  #
  #  ruby-1.9.2-head > ActiveRecord::Relation.instance_method(:find).source_with_doc
  #   => # Find operates with four different retrieval approaches:
  #  ...
  #  def find(*args, &block)
  #    return to_a.find(&block) if block_given?
  #
  #    options = args.extract_options!
  #
  #    if options.present?
  #  ...
  def source_with_doc
    return unless source_location

    [doc.to_s.chomp, source_unindent(source)].compact.reject(&:empty?).join("\n")
  end

  def full_inspect
    "#{ inspect }\n#{ source_location }\n#{ source_with_doc }"
  end

  private

  def source_unindent(src)
    lines = src.split("\n")
    indented_lines = lines[1 .. -1] # first line doesn't have proper indentation
    indent_level = indented_lines.
            reject { |line| line.strip.empty? }. # exclude empty lines from indent level calculation
            map { |line| line[/^(\s*)/, 1].size }. # map to indent level of every line
            min
    [lines[0], *indented_lines.map { |line| line[indent_level .. -1] }].join("\n")
  end
  
  class ::Method
    include MethodSourceWithDoc
  end

  class ::UnboundMethod
    include MethodSourceWithDoc
  end

  class MethodSourceRipper < Ripper
    def self.source_from_source_location(source_location)
      return unless source_location
      new(*source_location).method_source
    end

    def initialize(filename, method_definition_lineno)
      super(IO.read(filename), filename)
      @src_lines = IO.read(filename).split("\n")
      @method_definition_lineno = method_definition_lineno
    end

    def method_source
      parse
      if @method_source
        @method_source
      else
        raise ArgumentError.new("failed to find method definition around the lines:\n" <<
                definition_lines.join("\n"))
      end
    end

    def definition_lines
      @src_lines[@method_definition_lineno - 1 .. @method_definition_lineno + 1]
    end

    Ripper::SCANNER_EVENTS.each do |meth|
      define_method("on_#{ meth }") do |*args|
        [lineno, column]
      end
    end

    def on_def(name, params, body)
      from_lineno, from_column = name
      return unless @method_definition_lineno == from_lineno

      to_lineno, to_column = lineno, column

      @method_source = @src_lines[from_lineno - 1 .. to_lineno - 1].join("\n").strip
    end

    def on_defs(target, period, name, params, body)
      on_def(target, params, body)
    end
  end

  class MethodDocRipper < Ripper
    def self.doc_from_source_location(source_location)
      return unless source_location
      new(*source_location).method_doc
    end

    def initialize(filename, method_definition_lineno)
      super(IO.read(filename), filename)
      @method_definition_lineno = method_definition_lineno
      @last_comment_block = nil
    end

    def method_doc
      parse
      @method_doc
    end

    Ripper::SCANNER_EVENTS.each do |meth|
      define_method("on_#{ meth }") do |token|
        if @last_comment_block &&
                lineno == @method_definition_lineno
          @method_doc = @last_comment_block.join.gsub(/^\s*/, "")
        end

        @last_comment_block = nil
      end
    end

    def on_comment(token)
      (@last_comment_block ||= []) << token
    end

    def on_sp(token)
      @last_comment_block << token if @last_comment_block
    end
  end
end if ripper_available
