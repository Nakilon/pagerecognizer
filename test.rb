require "minitest/autorun"

require "ferrum"
require_relative "lib/pagerecognizer"
PageRecognizer.logger.level = :INFO

describe PageRecognizer do
  before do
    options = {}
    options[:browser_options] = {"no-sandbox": nil} if ENV.has_key? "FERRUM_NO_SANDBOX"
    options[:headless] = false if ENV.has_key? "HEADFULL"
    @browser = Ferrum::Browser.new **options
  end
  after do
    @browser&.quit
  end

  [
      ["google1.htm", [
        ["https://ru.wikipedia.org/wiki/Ruby#:~:te", "Ruby — Википедия"],
        ["https://www.ruby-lang.org/ru/", "Язык программирования Ruby"],
        ["https://ru.wikibooks.org/wiki/Ruby", "Ruby — Викиучебник"],
        ["https://habr.com/ru/post/433672/", "Пацаны, так Ruby умер или нет? / Хабр - Habr"],
        ["https://habr.com/ru/hub/ruby/", "Ruby – Динамический высокоуровневый язык..."],
        ["https://web-creator.ru/articles/ruby", "Язык программирования Ruby - Веб Креатор"],
        ["http://rusrails.ru/", "Rusrails: Ruby on Rails по-русски"],
        ["https://vc.ru/dev/72391-pochemu-my-vybir", "Почему мы выбираем Ruby для наших проектов..."],
        ["https://tproger.ru/tag/ruby/", "Ruby — всё по этой теме для программистов..."],
        ["https://rubyrussia.club/", "RubyRussia"],
      ] ],
      ["google2.mht", [
        ["https://www.ruby-lang.org/ru/", "Язык программирования Ruby"],
        ["https://ru.wikipedia.org/wiki/Ruby", "Ruby - Википедия"],
        ["https://evrone.ru/why-ruby", "5 причин, почему мы выбираем Ruby - evrone.ru"],
        ["https://habr.com/ru/hub/ruby/", "Ruby — Динамический высокоуровневый язык..."],
        ["https://ru.wikibooks.org/wiki/Ruby", "Ruby - Викиучебник"],
        ["https://context.reverso.net/%D0%BF%D0%B5", "ruby - Перевод на русский - примеры английский..."],
        ["https://web-creator.ru/articles/ruby", "Язык программирования Ruby - Веб Креатор"],
        ["https://ru.hexlet.io/courses/ruby", "Введение в Ruby - Хекслет"],
        ["https://rubyrush.ru/articles/what-is-rub", "Что такое Ruby on Rails?"],
      ] ],
  ].each do |filename, expectation|
    it "google rows #{filename}" do
    @browser.goto "file://#{File.expand_path filename}"
    results = @browser.at_css("body").rows([:AREA, :SIZE], try_min: 9) do |node|
      texts = node.texts
      next if texts.none?{ |_, _, color, | :black == color }
      _, group = texts.group_by{ |_, style, | style["fontSize"].to_i }.to_a.max_by(&:first)
      next unless group
      next unless group.size == 1 && %i{ blue navy }.include?(group[0][2])
      true
    end
    assert_equal expectation, results.reject{ |_| _.node.at_css "img" }.map{ |result| [
      result.node.at_css("a").property("href")[0,40],
      result.texts.max_by{ |_, style, | style["fontStyle"].to_i }[0].sub(/(.{40}) .+/, "\\1..."),
    ] }
    end
  end
  [
      ["youtube.htm", %w{ Главная В\ тренде Подписки Библиотека История }, 8],
      ["youtube2.mht", %w{ Главная Навигатор Shorts Подписки Библиотека История }, 10],
  ].each do |filename, expected_navigation, rows|
    it "youtube rows grid #{filename}" do
      @browser.goto "file://#{File.expand_path filename}"
      assert_equal expected_navigation, @browser.at_css("ytd-mini-guide-renderer").rows([:AREA, :SIZE]){ |_| !_.node.text.strip.empty? }.map{ |nav| nav.texts.first[0] }
      grid = @browser.at_css("#content").grid
      assert_equal 3*rows, grid.size
      assert_equal [3]*rows, grid.rows.map(&:size)
      assert_equal [rows]*3, grid.cols.map(&:size)
      grid.each{ |n| n.to_h.values_at(:width, :height).each{ |_| assert_in_delta 250, _, 50 } }
    end
  end
  [
    ["yandex.mht", [
      ["https://www.ruby-lang.org/ru/", "Язык программирования Ruby"],
      ["https://www.ruby-lang.org/", "Ruby Programming Language"],
      ["https://www.ruby-lang.org/en/", "Ruby Programming Language"],
      ["https://ru.wikipedia.org/wiki/Ruby", "Ruby — Википедия"],
      ["https://en.wikipedia.org/wiki/Ruby_(prog", "Ruby (programming language) - Wikipedia"],
      ["https://developer.oracle.com/ruby/what-i", "What is Ruby? | Oracle Developer"],
      ["https://github.com/ruby/ruby", "GitHub - ruby/ruby: The Ruby Programming Language [mirror]"],
      ["https://www.opennet.ru/docs/RUS/ruby_gui", "Ruby - Руководство пользователя"],
      ["https://www.youtube.com/playlist?list=PL", "Изучение Ruby для начинающих - YouTube"],
      ["https://medium.com/nuances-of-programmin", "Основы программирования на Ruby. Что такое Ruby?"],
    ] ],
  ].each do |filename, expectation|
    it "yandex rows #{filename}" do
      @browser.goto "file://#{File.expand_path filename}"
      nodes = @browser.at_css("body").rows([:AREA, :SIZE], try_min: 9) do |node|
        node.node.at_css("a") &&
        node.node.at_css("a").property("href")[/(?<=\/)[^\/]+/] != "yabs.yandex.ru"
      end
      assert_equal expectation, nodes.group_by(&:left).values.max_by(&:size).map{ |result| [
        result.node.at_css("a").property("href")[0,40],
        result.node.at_css("a").text,
      ] }
    end
  end
end
