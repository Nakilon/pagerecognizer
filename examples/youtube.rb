require "ferrum"
require_relative "../lib/pagerecognizer"
Ferrum::Node.include PageRecognizer
browser = Ferrum::Browser.new headless: false
PageRecognizer.logger.level = :INFO

browser.goto "https://youtube.com/"
browser.wait_for_reload 1

navigation = browser.at_css("ytd-mini-guide-renderer").rows([:AREA, :SIZE], dump: "dump"){ |_| !_.node.text.strip.empty? }
File.write "dump.navigation.htm", navigation.dump
p navigation.map{ |nav| nav.texts.first[0] }

grid = browser.at_css("#content").grid "dump"
File.write "dump.htm", grid.dump

puts "#{grid.cols.size} x #{grid.rows.size}"
