require "minitest/autorun"
require "ferrum"
require_relative "lib/pagerecognizer"

describe PageRecognizer do
  it "google split" do
    browser = Ferrum::Browser.new **(ENV.has_key?("FERRUM_NO_SANDBOX") ? {browser_options: {"no-sandbox": nil}} : {})
    browser.goto "about:blank"
    browser.execute "document.write(#{File.read("google.htm").inspect})"
    results = browser.at_css("body").rows
    width = results.group_by(&:width).max_by{ |w, g| g.size }.first
    assert_equal [
      ["https://www.ruby-lang.org/ru/", "Ruby это... динамический язык программирования с о"],
      ["https://ru.wikibooks.org/wiki/Ruby", "Этот учебник намерен осветить все тонкости програм"],
      ["https://habr.com/ru/post/433672/", "19 дек. 2018 г. - Взрывной рост интереса к Ruby ос"],
      ["https://habr.com/ru/hub/ruby/", "Ruby (англ. Ruby — «Рубин») — динамический, рефлек"],
      ["https://web-creator.ru/articles/ruby", "Ruby разрабатывался на Linux, но работает на многи"],
      ["http://rusrails.ru/", "Ruby on Rails руководства, учебники, статьи на рус"],
      ["https://vc.ru/dev/72391-pochemu-my-vybiraem-ruby-d", "20 июн. 2019 г. - Ruby on Rails одним из первых на"],
      ["https://tproger.ru/tag/ruby/", "Django или Ruby on Rails: какой фреймворк выбрать?"],
      ["https://rubyrussia.club/", "Главная российская конференция о Ruby. Расширяем г"]
    ], results.select{ |r| r.width == width }.map(&:node).map(&:rows).map{ |link, desc| [
      link.node.at_css("a").property("href")[0,50],
      desc.node.text[0,50],
    ] }
    browser.quit
  end
  it "youtube grid" do
    browser = Ferrum::Browser.new **(ENV.has_key?("FERRUM_NO_SANDBOX") ? {browser_options: {"no-sandbox": nil}} : {})
    browser.goto "about:blank"
    browser.execute "document.write(#{File.read("youtube3.htm").inspect})"
    results = browser.at_css("#content").grid
    assert_equal 24, results.size
    assert results.flat_map{ |n| n.to_h.values_at :width, :height }.all?{ |_| (_-275).abs < 25 }
    browser.quit
  end
end
