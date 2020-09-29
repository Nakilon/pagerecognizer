Gem::Specification.new do |spec|
  spec.name         = "pagerecognizer"
  spec.version      = "0.0.1"
  spec.summary      = "visual HTML page structure recognizer"

  spec.author       = "Victor Maslov aka Nakilon"
  spec.email        = "nakilon@gmail.com"
  spec.license      = "MIT"
  spec.metadata     = {"source_code_uri" => "https://github.com/nakilon/pagerecognizer"}

  spec.add_dependency "ferrum"
  spec.add_dependency "nokogiri"
  spec.add_dependency "pcbr", "~>0.4.2"
  spec.add_development_dependency "minitest"

  spec.add_development_dependency "ruby-prof"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency "mll"

  spec.require_path = "lib"
  spec.test_file    = "test.rb"
  spec.files        = %w{ LICENSE pagerecognizer.gemspec lib/pagerecognizer.rb }
end
