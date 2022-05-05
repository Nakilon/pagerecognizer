[![Gem Version](https://badge.fury.io/rb/pagerecognizer.svg)](http://badge.fury.io/rb/pagerecognizer)
[![Test](https://github.com/nakilon/pagerecognizer/workflows/.github/workflows/test.yaml/badge.svg)](https://github.com/Nakilon/pagerecognizer/actions)

# Pagerecognizer -- the visual web page structure recognizing A.I. tool

The idea is to forget that DOM is a tree and view the page like a human would do. Then apply smart algorithms to recognize the main blocks that really form a UI.
This is particularly useful in test automation because HTML/CSS internals are changing more frequently than design.

### Example of splitting in rows (also check [`./google.example.rb`](google.example.rb) for some other details):

I'll show how to use this tool on www.google.com as an exmple. The HTML page of it might already have some convenient ids or classes but let's pretend there are none. Currently the gem utilizes the Ferrum so you may already know some basic methods:
```ruby
require "ferrum"
require "pagerecognizer"
Ferrum::Node.include PageRecognizer

browser = Ferrum::Browser.new
browser.goto "https://google.com/"
```
Let's call the private method `#recognize` just to see what it would see and export the result like this:
```ruby
File.write "dump.htm", browser.at_css("body").send(:recognize).dump
```

![](http://gems.nakilon.pro.storage.yandexcloud.net/pagerecognizer/google.png)

This is a nodes rects view that the A.I. will use later for the recognition. Let's do a web search and see what it sees now:
```ruby
browser.at_css("input[type=text]").focus.type "Ruby", :enter
```

![](http://gems.nakilon.pro.storage.yandexcloud.net/pagerecognizer/ruby.png)

Now let's try the magic method `#rows` and see if it has recognized the search results sections of the page.
```ruby
File.write "dump.htm", browser.at_css("body").rows([:AREA, :SIZE]).dump
```
`:AREA` and `:SIZE` are the recommended euristics for the `rows` and `cols` methods, you can find others in the source code.

![](http://gems.nakilon.pro.storage.yandexcloud.net/pagerecognizer/rows.png)

The Google Search page is complex today and as you can see with the default options it did not recognize the first result and misrecognized others. The misrecognized ones either have no blue hyperlinks or no text at all. What can we do? Each recognized node has a method `#texts` that allows us to access the text blocks and their style. It also recognizes text color classifying it based on [16 Basic Web colors](https://en.wikipedia.org/wiki/Web_colors#Basic_colors). Let's use it and add a custom euristic that would give a hint to process only such nodes that contain black and blue text:
```ruby
results = browser.at_css("body").rows([:AREA, :SIZE]) do |node|
  colors = node.texts.map{ |text, style, color, | color }
  colors.any?{ |c| :black == c } &&
  colors.any?{ |c| :blue == c || :navy == c }
end
File.write "dump.htm", results.dump
```

![](http://gems.nakilon.pro.storage.yandexcloud.net/pagerecognizer/blackblue.png)

Custom euristic not only helps the A.I. but also may make the recognition faster because it makes less nodes to process. It still picks wrong nodes though. Then let's select such that the biggest text in them is blue and happens only once. Also throw out the nodes with images because we are not interested in video results (note that we use `.node` since the `node` is a recognized object, a structure, and `.node` is the actual Ferrum object):
```ruby
... do |node|
  texts = node.texts
  next if texts.none?{ |text, style, color, | :black == color }
  _, group = texts.group_by{ |text, style, | style["fontSize"].to_i }.to_a.max_by(&:first)
  next unless group  # the largest text should be blue
  next unless group.size == 1 && %i{ blue navy }.include?(group[0][2])
  next if node.node.at_css "img"  # we aren't interested in video results
  true
end
```

![](http://gems.nakilon.pro.storage.yandexcloud.net/pagerecognizer/perfect.png)

Perfect. Now we can parse them:
```ruby
results.map do |result|
  [
    result.node.at_css("a").property("href")[0,40],
    result.texts.max_by{ |t, s, | s["fontStyle"].to_i }[0].sub(/(.{40}) .+/, "\\1..."),
  ]
end
```
```none                                                                 
  https://ru.wikipedia.org/wiki/Ruby         Ruby - Википедия                                   
  https://www.ruby-lang.org/ru/              Язык программирования Ruby                         
  https://evrone.ru/why-ruby                 5 причин, почему мы выбираем Ruby - evrone.ru      
  https://habr.com/ru/hub/ruby/              Ruby — Динамический высокоуровневый язык...        
  https://ru.wikibooks.org/wiki/Ruby         Ruby - Викиучебник                                 
  https://context.reverso.net/%D0%BF%D0%B5   ruby - Перевод на русский - примеры английский...  
  https://web-creator.ru/articles/ruby       Язык программирования Ruby - Веб Креатор           
  https://ru.hexlet.io/courses/ruby          Введение в Ruby - Хекслет                          
  https://www.ozon.ru/product/yazyk-progra   Книга "Язык программирования Ruby" - OZON        
```
We've just scraped the SERP knowing nothing about its DOM other that there are big blue links with black descriptions!

### Example of grid detection

```ruby
browser.goto "https://youtube.com/"
grid = browser.at_css("#content").grid

grid.size              # => 24
grid.cols.size         # => 3
grid.cols.map(&:size)  # => [8, 8, 8]
grid.rows.size         # => 8
grid.rows.map(&:size)  # => [3, 3, 3, 3, 3, 3, 3, 3]
```
![](http://gems.nakilon.pro.storage.yandexcloud.net/pagerecognizer/youtube.grid.png)


