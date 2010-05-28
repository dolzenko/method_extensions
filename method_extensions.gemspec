lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
 
Gem::Specification.new do |s|
  s.name        = "method_extensions"
  s.version     = "0.0.2"
  s.authors     = ["Evgeniy Dolzhenko"]
  s.email       = ["dolzenko@gmail.com"]
  s.homepage    = "http://github.com/dolzenko/method_extensions"
  s.summary     = "Method object extensions for better code navigation"
  s.files       = Dir.glob("lib/**/*") + %w(method_extensions.gemspec)
end