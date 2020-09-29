[![Gem Version](https://badge.fury.io/rb/pagerecognizer.svg)](http://badge.fury.io/rb/pagerecognizer)
[![Test](https://github.com/nakilon/pagerecognizer/workflows/.github/workflows/test.yaml/badge.svg)](https://github.com/Nakilon/pagerecognizer/actions)

The idea is to forget that DOM is a tree and view the page as a human. Then apply smart algorithms to recognize the main blocks that really form a UI.
This is particularly useful in test automation because HTML/CSS internals are changing more frequently than design.

### Example of splitting in cols and rows ([google.example.rb](google.example.rb) is much more updated than this readme):

Let's open a website:
```ruby
require "ferrum"
require_relative "lib/pagerecognizer"
Ferrum::Node.include PageRecognizer

browser = Ferrum::Browser.new
browser.goto "https://google.com/"
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/google.com.png)  
Now `#recognize` elements that matter:
```ruby
File.write "dump.htm", browser.at_css("body").recognize.dump
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/google.com.recognized.jpg)  
Ok, let's try something more complex:
```ruby
browser.at_css("input[type=text]").focus.type "Ruby", :enter
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/ruby.recognized_.jpg)  
Or find the main vertical sections (`#rows`) that the page consists of:
```ruby
browser.at_css("body").rows
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/ruby.rows.png)  
Now if we do the same thing to the largest block we've just found:  
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/ruby.main.jpg)  
You may already have a guess how to find which of these are text results.  
The rest is simple. Full example script is included in this repo:
```none
$ bundle install && bundle exec ruby google.example.rb
                                                                                                                              
  https://www.ruby-lang.org/ru/                                           Ruby это... динамический язык программирования...   
  https://ru.wikibooks.org/wiki/Ruby                                      Этот учебник намерен осветить все тонкости...       
  https://habr.com/ru/post/433672/                                        19 дек. 2018 г. - Взрывной рост интереса...         
  https://habr.com/ru/hub/ruby/                                           Секрет в том, что на Ruby можно быстро написать...  
  https://web-creator.ru/articles/ruby                                    Ruby разрабатывался на Linux, но работает...        
  http://rusrails.ru/                                                     Ruby on Rails руководства, учебники, статьи...      
  https://vc.ru/dev/72391-pochemu-my-vybiraem-ruby-dlya-nashih-proektov   20 июн. 2019 г. - Ruby on Rails одним из...         
  https://tproger.ru/tag/ruby/                                            Django или Ruby on Rails: какой фреймворк...        
```
Yay! We have just scraped Google Search results page knowing only that it has `<body>` and `<a>` tags and nothing else about attributes or DOM structure.

### Example of grid detection

```ruby
browser.goto "https://youtube.com/"
File.write "temp.htm", browser.at_css("#content").grid.dump
```
![](https://storage.googleapis.com/pagerecognizer.nakilon.pro/youtube.grid.png)  

