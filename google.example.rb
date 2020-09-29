require "ferrum"                              # currently only Ferrum is supported but it should be trivial to add Selenium
require_relative "lib/pagerecognizer"         # or `require "pagerecognizer"` if you are using it as a gem
Ferrum::Node.include PageRecognizer           # here we add Ferrum nodes the magic methods

browser = Ferrum::Browser.new headless: false
browser.goto "https://google.com/"
browser.at_css("input[type=text]").focus.type "Ruby", :enter
sleep 2   # https://github.com/rubycdp/ferrum/issues/114

results = browser.at_css("body").rows       # Array of Structs that have a `.node` attribute (`Ferrum::Node`)
File.write "temp1.htm", results.dump
# this .htm file is a dump -- that colored thing from docs
# (there is also a method `PageRecognizer.load` to load a dump for later observation)
# now if we observe the dump we'll see that we need those 9 blocks with the same width
width = results.group_by(&:width).max_by{ |_, g| g.size }.first
splitted = results.select{ |r| r.width == width }.map(&:node).map{ |i| i.rows :SIZE, :AREA, :MIDDLE }

# if you want to see how every result was splitted, join them and dump like this
File.write "temp2.htm", splitted.flatten(1).extend(PageRecognizer::Dumpable).dump


require "mll"   # just an old fancy gem of mine for printing a table
puts MLL.grid.call splitted.map{ |link, desc| [
  link.node.at_css("a").property("href")[0,40],
  desc.node.text.sub(/(.{40}) .+/, "\\1..."),
] }, spacings: [2, 0], alignment: :left
