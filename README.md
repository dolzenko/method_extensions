## method_extensions

Adds the following method to the `Method/UnboundMethod` objects

  * `source` - finds method source based on `source_location` and `Ripper` parser
  * `doc` - returns the comment preceding method definition
  * `super` - returns method which will be called if given `Method/UnboundMethod` would
    call `super`. Chainable. Available only after you `require "method_extensions/method/super"`

And some sugar

  * `source_with_doc` - `source` + `doc`
  * `full_inspect` - `inspect` + `source_location` + `source_with_doc`

## Installation

    gem install method_extensions

## Usage

    > irb
    ruby-1.9.2-head > require "method_extensions"
    ruby-1.9.2-head > require "fileutils"
    ruby-1.9.2-head > puts FileUtils.method(:mkdir).source_with_doc
    #
    # Options: mode noop verbose
    #
    # Creates one or more directories.
    #
    #   FileUtils.mkdir 'test'
    #   FileUtils.mkdir %w( tmp data )
    #   FileUtils.mkdir 'notexist', :noop => true  # Does not really create.
    #   FileUtils.mkdir 'tmp', :mode => 0700
    #
    def mkdir(list, options = {})
      fu_check_options options, OPT_TABLE['mkdir']
      list = fu_list(list)
      fu_output_message "mkdir #{options[:mode] ? ('-m %03o ' % options[:mode]) : ''}#{list.join ' '}" if options[:verbose]
      return if options[:noop]

      list.each do |dir|
        fu_mkdir dir, options[:mode]
      end
    end


    ruby-1.9.2-head > eval <<-CODE 
      class Base
        def meth; end
      end

      class Derived < Base
        def meth; end
      end
    CODE

    ruby-1.9.2-head > Derived.instance_method(:meth)
    => #<UnboundMethod: Derived#meth>

    ruby-1.9.2-head > Derived.instance_method(:meth).super
    => #<UnboundMethod: Base#meth>
