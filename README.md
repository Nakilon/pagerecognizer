example

```ruby
require "ferrum"
require_relative "lib/pagerecognizer"
Ferrum::Node.include PageRecognizer

browser = Ferrum::Browser.new
browser.goto "https://google.com/"
File.write "1.htm", browser.at_css("body").recognize.visualize

browser.at_css("input[type=text]").focus.type "Ruby", :enter
sleep 2

File.write "2.htm", browser.at_css("body").recognize.visualize
```
