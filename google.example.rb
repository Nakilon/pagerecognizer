require "ferrum"                              # currently only Ferrum is supported but it should be trivial to add Selenium
require_relative "lib/pagerecognizer"
# PageRecognizer.logger.level = Logger::DEBUG # loglevel is FATAL by default
Ferrum::Node.include PageRecognizer           # here we add Ferrum nodes the magic methods

# it can run headless but we want to watch
browser = Ferrum::Browser.new headless: false
browser.goto "https://google.com/"
browser.at_css("input[type=text]").focus.type "Ruby", :enter
browser.wait_for_reload 1   # https://github.com/rubycdp/ferrum/issues/114

results = browser.at_css("body").rows([:AREA, :SIZE]) do |node|
  # `node` is a search result candidate we want to apply some checks to
  texts = node.texts
  next if texts.none?{ |text, style, color, | :black == color }
  _, group = texts.group_by{ |text, style, | style["fontSize"].to_i }.to_a.max_by(&:first)
  next unless group  # the largest text should be blue
  next unless group.size == 1 && %i{ blue navy }.include?(group[0][2])
  next if node.node.at_css "img"  # we aren't interested in video results
  true
end
puts "#{results.size} search results"
File.write "dump.htm", results.dump

# this .htm file is a dump -- that colored thing from docs
# (there is also a method `PageRecognizer.load` to load a dump for later inspection)

results.map(&:node).each{ |_| browser.execute "arguments[0].style['background-color'] = 'yellow'", _ }
gets  # we paint the found nodes in yellow to observe

require "mll"   # just an old fancy gem of mine that can print tables
puts MLL.grid.call results.map{ |result| [
  result.node.at_css("a").property("href")[0,40],
  result.texts.max_by{ |t, s, | s["fontStyle"].to_i }[0].sub(/(.{40}) .+/, "\\1..."),
] }, spacings: [2, 0], alignment: :left
