require "minitest/autorun"

require "ferrum"
require_relative "lib/pagerecognizer"
# PageRecognizer.logger.level = :DEBUG

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
  it "google rows" do
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
    ].each do |test_file, expectation|

    @browser.goto "file://#{File.expand_path test_file}"
    results = @browser.at_css("body").rows([:AREA, :SIZE], try_min: 9) do |node|
      texts = node.texts
      next if texts.none?{ |_, _, color, | :black == color }
      _, group = texts.group_by{ |_, style, | style["fontSize"].to_i }.to_a.max_by(&:first)
      next unless group
      next unless group.size == 1 && %i{ blue navy }.include?(group[0][2])
      next if node.node.at_css "img"
      true
    end
    assert_equal expectation, results.map{ |result| [
      result.node.at_css("a").property("href")[0,40],
      result.texts.max_by{ |_, style, | style["fontStyle"].to_i }[0].sub(/(.{40}) .+/, "\\1..."),
    ] }

    end
  end
  it "youtube cols grid" do
    @browser.goto "about:blank"
    @browser.execute "document.write(#{File.read("youtube.htm").inspect})"
    assert_equal %w{ Главная В\ тренде Подписки Библиотека История }, @browser.at_css("ytd-mini-guide-renderer").rows([:AREA, :SIZE]).map(&:node).map(&:text).map(&:strip)
    results = @browser.at_css("#content").grid
    assert_equal 24, results.size
    assert results.flat_map{ |n| n.to_h.values_at :width, :height }.all?{ |_| (_-275).abs < 25 }
    assert_equal [3]*8, results.rows.map(&:size)
    assert_equal [8]*3, results.cols.map(&:size)
  end
end
