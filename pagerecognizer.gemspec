Gem::Specification.new do |spec|
  spec.name         = "pagerecognizer"
  spec.version      = "0.0.0"
  spec.summary      = "visual HTML page structure recognizer"

  spec.author       = "Victor Maslov aka Nakilon"
  spec.email        = "nakilon@gmail.com"
  spec.license      = "MIT"
  spec.metadata     = {"source_code_uri" => "https://github.com/nakilon/pagerecognizer"}

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "ferrum"
  spec.add_development_dependency "ruby-prof"
  spec.add_development_dependency "byebug"

  spec.require_path = "lib"
  spec.test_file    = "test.rb"
  spec.files        = %w{ LICENSE.txt pagerecognizer.gemspec lib/pagerecognizer.rb }
end
