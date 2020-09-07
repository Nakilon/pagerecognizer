The idea is to forget that DOM is a tree and look at page as a human. Then apply smart algorithms to recognize the main blocks.

Example:

```ruby
require "ferrum"
require_relative "lib/pagerecognizer"
Ferrum::Node.include PageRecognizer

browser = Ferrum::Browser.new
browser.goto "https://google.com/"
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/google.com.png)
```ruby
File.write "1.htm", browser.at_css("body").recognize.visualize
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/google.com.recognized.jpg)  
```ruby
browser.at_css("input[type=text]").focus.type "Ruby", :enter
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/ruby.jpg)
```ruby
sleep 2

File.write "2.htm", browser.at_css("body").recognize.visualize
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/ruby.recognized.jpg)
