require "yaml"

GEM_NAME = "method_extensions"

new_version = ENV["GEM_VERSION"]

puts "Releasing #{ GEM_NAME } #{ new_version }"

system "gem build #{ GEM_NAME }.gemspec --verbose"

system "gem push #{ GEM_NAME }-#{ new_version }.gem --verbose"

system "gem install #{ GEM_NAME } --version=#{ new_version } --local --verbose"

File.delete("#{ GEM_NAME }-#{ new_version }.gem")

system "git push"

