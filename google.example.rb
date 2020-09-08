require "ferrum"
require_relative "lib/pagerecognizer"
Ferrum::Node.include PageRecognizer
PageRecognizer.logger.level = Logger::WARN

browser = Ferrum::Browser.new headless: !ARGV[0]

browser.goto "https://google.com/"
browser.at_css("input[type=text]").focus.type "Ruby", :enter
sleep 2

rows = browser.at_css("body").rows
results = rows.max_by(&:area).node.rows
width = results.group_by(&:width).max_by{ |w,g| g.size }.first
splitted = results.select{ |r| r.width == width }.map(&:node).map(&:rows).compact

require "mll"
puts MLL.grid.call splitted.map{ |link, desc| [
  link.node.at_css("a").property("href"),
  desc.node.text.sub(/(.{40}) .+/, "\\1..."),
] }, spacings: [2, 0], alignment: :left
