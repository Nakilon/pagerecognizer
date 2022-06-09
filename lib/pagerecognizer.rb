module PageRecognizer
  class << self
    attr_accessor :logger
  end
  require "logger"
  self.logger = Logger.new STDOUT
  self.logger.formatter = ->(severity, datetime, progname, msg){ "#{datetime.strftime "%H%M%S"} #{severity.to_s[0]} #{msg}\n" }
  self.logger.level = ENV.fetch("LOGLEVEL_PageRecognizer", "FATAL").to_sym

  module Dumpable
    def dump
      "<html><body style='white-space: nowrap'>#{
        map.with_index do |n, i|
          "<div id='#{i}' style='position: absolute; background-color: hsla(#{
            360 * i / size
          },100%,50%,0.5); top: #{n.top}; left: #{n.left}; width: #{n.width}; height: #{n.height}'>#{i} #{
            n.node.tag_name.upcase
          }</div>"
        end.join
      }</body></html>"
    end
  end

  def self.load str
    require "nokogiri"
    Nokogiri::HTML(str).css("div").map do |n|
      Struct.new(*%i{ node top left width height }).new Struct.new(:tag_name).new(n.text),
        *n[:style].scan(/(\S+): ([^\;]+)/).to_h.values_at(
                      *%w{ top left width height }
        ).map(&:to_f)
    end.extend Dumpable
  end

  def self.rgb2hsv r, g, b   # [<256, <256, <256]
    # http://stackoverflow.com/q/41926874/322020
    r, g, b  = [r, g, b].map{ |_| _.fdiv 255 }
    min, max = [r, g, b].minmax
    chroma   = max - min
    [
      60.0 * ( chroma.zero? ? 0 : case max
        when r ; (g - b) / chroma
        when g ; (b - r) / chroma + 2
        when b ; (r - g) / chroma + 4
        else 0
      end % 6 ),
      chroma.zero? ? 0.0 : chroma / max,
      max,
    ]   # [<=360, <=1, <=1]
  end
  def self.dist h1, s1, v1, h2, s2, v2   # [<256, <256, <256]
    # https://en.wikipedia.org/wiki/HSL_and_HSV#/media/File:Hsl-hsv_saturation-lightness_slices.svg
    c1, c2 = s1 * v1 / 256.0, s2 * v2 / 256.0   # chroma
    z1, z2 = v1 * (2 - c1 / 256), v2 * (2 - c2 / 256)
    a = (((h2 - h1) * 360 / 256.0) % 360) / (180 / Math::PI)
        x2 =     Math::sin(a) * c2
    y1, y2 = c1, Math::cos(a) * c2
    x2*x2 + (y1-y2)*(y1-y2) + (z1-z2)*(z1-z2)
  end

  private def recognize
    logger = Module.nesting.first.logger
    logger.info "method #{__method__}..."

    nodes = []
    try = lambda do
      str = Struct.new :node, :visible, :top, :left, :width, :height, :area do
        def texts
          node.page.evaluate(<<~HEREDOC, node).map(&JSON.method(:load)).map do |text, rect1, rect2, style|
            (function(node){
              let result = [], range = document.createRange();
              for (
                let iterator = document.evaluate('.//text()', node, null, XPathResult.ANY_TYPE, null);
                text = iterator.iterateNext();
              ) {
                range.selectNode(text);
                let rect1 = range.getBoundingClientRect();
                let rect2 = text.parentNode.getBoundingClientRect();
                if (rect1.width >= 2 && rect1.height >= 2 && rect2.width >= 2 && rect2.height >= 2)
                  result.push(JSON.stringify( [text.wholeText, rect1, rect2, getComputedStyle(text.parentNode)] ));
                  // google SERP has 1x1 nodes with text _<>
              }
              return result;
            })(arguments[0])
          HEREDOC
            color = style["color"]
            fail color unless /\Argba?\((?<red>\d+), (?<green>\d+), (?<blue>\d+)(, 0(\.\d+)?)?\)\z/ =~ color
            closest_color = {   # https://en.wikipedia.org/wiki/Web_colors#Basic_colors
              white: [0, 0, 100],
              silver: [0, 0, 75],
              gray: [0, 0, 50],
              black: [0, 0, 0],
              red: [0, 100, 100],
              maroon: [0, 100, 50],
              yellow: [60, 100, 100],
              olive: [60, 100, 50],
              lime: [120, 100, 100],
              green: [120, 100, 50],
              aqua: [180, 100, 100],
              teal: [180, 100, 50],
              blue: [240, 100, 100],
              navy: [240, 100, 50],
              fuchsia: [300, 100, 100],
              purple: [300, 100, 50],
            }.to_a.min_by do |_, (h1, s1, v1)|
              h2, s2, v2 = PageRecognizer.rgb2hsv(red.to_i, green.to_i, blue.to_i)
              PageRecognizer.dist h1*255/360, s1*256/100, v1*256/100, h2*255/360, s2*255, v2*255
            end.first
            [text, style, closest_color, rect1]
          end.compact
        end
      end
      prev = nodes.size
      t = page.evaluate(<<~HEREDOC, self)
        ( function(node) {
          var x = scrollX, y = scrollY;
          var _tap = function(x, f){ f(); return x };
          var f = function(node) {
            node.scrollIntoView();
            var rect = JSON.parse(JSON.stringify(node.getBoundingClientRect()));
            rect.top += scrollY;
            rect.left += scrollX;
            return [
              node, JSON.stringify([("visible" == getComputedStyle(node).visibility), rect.top, rect.left, rect.width, rect.height])
            ].concat(Array.from(node.childNodes).filter(function(node) { return node.nodeType == 1 }).flatMap(f));
          };
          return _tap(f(node), function(){ scrollTo(x, y) });
        } )(arguments[0])
      HEREDOC
p Time.now
      logger.debug [t.size / 2, prev]
      nodes = t.each_slice(2).map{ |node, rect_visible| str.new(node, *JSON.load(rect_visible)).tap{ |_| _.area = _.width * _.height } }
      nodes.size == prev
    end

    if defined? Selenium::WebDriver::Wait
      Selenium::WebDriver::Wait.new(
        message: "either number of DOM elements didn't stop to change or recognition took too long"
      ).until &try
    else
      t = Time.now
      until try.call
        fail "either number of DOM elements didn't stop to change or recognition took too long" if Time.now > t + 10
      end
    end
    logger.info "#{nodes.size} DOM nodes found"
    nodes.reject!{ |_| _.height.zero? || _.width.zero? || !_.visible }
    logger.info "visible nodes: #{nodes.size}"
    nodes.extend Dumpable
  end

  logging_error = Class.new RuntimeError do
    attr_reader :dumps
    def initialize msg, arrays
      Module.nesting.first.logger.error "#{self.class}: #{msg}"
      @dumps = arrays.map{ |name, array| [name, array.extend(Dumpable).dump] }.to_h
      super msg
    end
  end
  class ErrorNotEnoughNodes < logging_error ; end

  private def split hh, ww, tt, ll, heuristics, try_min, dump, &filter
    logger = Module.nesting.first.logger
    logger.info heuristics

    unstale = unless defined? Selenium::WebDriver::Error::StaleElementReferenceError
      ->(&b){ b.call }
    else
      lambda do |&try|
        t = Time.now
        begin
          try.call
        rescue Selenium::WebDriver::Error::StaleElementReferenceError
          raise if Time.now > t + 10
          retry
        end
      end
    end

    nodes = unstale.call do recognize end.sort_by{ |_| [_[tt], _[ll]] }
    File.write "#{dump}.all.htm", nodes.extend(Dumpable).dump if dump


    nodes = unstale.call do nodes.reject{ |_| %w{ button script svg path a img }.include? _.node.tag_name } end.uniq{ |_| [_[hh], _[ww], _[tt], _[ll]] }
    logger.info "good and unique: #{nodes.size}"   # only those that might be containers
    File.write "#{dump}.nodes.htm", nodes.extend(Dumpable).dump if dump

    interfere = lambda do |a, b|
      a[tt] < b[tt] + b[hh] &&
      b[tt] < a[tt] + a[hh]
    end


    rest = nodes.select.with_index do |a, i|
      nodes.each_with_index.none? do |b, j|
        next if i == j
        a[tt] >= b[tt] && a[tt] + a[hh] <= b[tt] + b[hh] &&
        a[ll] >= b[ll] && a[ll] + a[ww] <= b[ll] + b[ww] &&
        nodes.all?{ |c| interfere[a, c] == interfere[b, c] }
      end
    end
    logger.info "not nested: #{rest.size}"
    File.write "#{dump}.rest1.htm", rest.extend(Dumpable).dump if dump

    # 8 = max_results - 1, 3 = (from row size diff euristic)
    if try_min
      rest = rest.reject{ |_| _[hh] + _[hh]/3*(try_min - 1) > (rest.map{ |_| _[tt] + _[hh] }.max - rest.map(&tt).min) }
      logger.info "small enough: #{rest.size}"
    end
    File.write "#{dump}.rest2.htm", rest.extend(Dumpable).dump if dump

    rest.select! &filter
    logger.info "filtered: #{rest.size}"
    File.write "#{dump}.filtered.htm", rest.extend(Dumpable).dump if dump

    rest.sort_by!(&:area).reverse!
    File.write "#{dump}.sorted.htm", rest.extend(Dumpable).dump if dump

    require "pcbr"
    pcbr = PCBR.new
    is = []
    max, past = 0, Set.new
    prev = nil
    time = Time.now
    loop do
      si = (0...rest.size).reject do |i|
        # I don't shrink pcbr so this should be a safe optimization
        next true if is.last > i unless is.empty?
        # also we've sorted from large to small so it does not get stuck with the half of the page below the largest node

        next (logger.debug [i, 2]; true) if is.any?{ |j| i == j || interfere[rest[i], rest[j]] }
        next (logger.debug [i, 3]; true) if is.any?{ |j| rest[i][ww] > rest[j][ww] * 2 } if heuristics.include? :WIDTH
        next (logger.debug [i, 4]; true) if is.any?{ |j| rest[j][ww] > rest[i][ww] * 2 } if heuristics.include? :WIDTH
        next (logger.debug [i, 5]; true) if is.any?{ |j| rest[i][hh] > rest[j][hh] * 3 }
        next (logger.debug [i, 6]; true) if is.any?{ |j| rest[j][hh] > rest[i][hh] * 3 }
      end
      logger.debug [is, si]
      si.each do |i|
        sol = rest.values_at *is, i
        unless pcbr.set.include? [*is, i].sort
        logger.debug [is, i, sol.map(&:area).reduce(:+)]
        pcbr.store [*is, i].sort, [
          *( is.size                                                                                                                if heuristics.include? :SIZE   ),
          *( sol.map(&:area).reduce(:+)                                                                                             if heuristics.include? :AREA   ),
          # https://en.wikipedia.org/wiki/Mean_absolute_difference
          *( -sol.product(sol).map{ |s1, s2| (s1.height             - s2.height            ).abs }.reduce(:+) / sol.size / sol.size if heuristics.include? :HEIGHT ),
          *( -sol.product(sol).map{ |s1, s2| (s1[ll] + s1[ww] / 2.0 - s2[ll] - s2[ww] / 2.0).abs }.reduce(:+) / sol.size / sol.size if heuristics.include? :MIDDLE ),
        ]
          logger.debug "pcbr.table.size: #{pcbr.table.size}"
          if si.none? do |j|
            next if j <= i
            next true if interfere[rest[i], rest[j]]
            next true if rest[i][ww] > rest[j][ww] * 2 if heuristics.include? :WIDTH
            next true if rest[j][ww] > rest[i][ww] * 2 if heuristics.include? :WIDTH
            next true if rest[i][hh] > rest[j][hh] * 3
            next true if rest[j][hh] > rest[i][hh] * 3
          end
            logger.debug "forced"
            break
          end
        end
      end
      if prev && Time.now - time > 5
        logger.debug "check"
        break logger.info "break 0" if Time.now - time > 30
        break logger.info "break 1" if Time.now - prev > 10
        m = pcbr.table.reject{ |i| i.first.size < 2 }.map(&:last).max
        break logger.info "break 2" if Time.now - prev > (prev - time) && 1 == pcbr.table.count{ |i| i.last == m }
      end
      break logger.info "done" unless t = pcbr.table.reject{ |is,| past.include? is.map{ |i| 2**i }.reduce(:+) }.max_by(&:last)
      logger.debug "next: #{t}"
      past.add (is = t.first).map{ |i| 2**i }.reduce(:+)
      if t.last > max
        prev, max = Time.now, t.last
        logger.debug "new max: #{max}"
        logger.debug [Time.now - time, max, t.first]
      end
    end
    # TODO: if multiple with max score, take the max by area
    unless best = pcbr.table.reject{ |is,| is.size < 2 }.max_by(&:last)
      raise ErrorNotEnoughNodes.new "failed to split <#{tag_name}>", all: all, nodes: nodes, rest: rest
    end
    pcbr.table.max_by(20, &:last).each_with_index{ |_, i| logger.debug "##{i} #{_}" }
    logger.info best
    logger.info "splitted in #{best.first.size}"
    rest.values_at(*best.first).sort_by(&tt).extend Dumpable
  end

  def rows heuristics, try_min: nil, dump: nil, &b
    split :height, :width, :top, :left, heuristics, try_min, dump, &b
  end
  def cols heuristics, try_min: nil, dump: nil, &b
    split :width, :height, :left, :top, heuristics, try_min, dump, &b
  end

  def self.piles z
    max = nil
    result = [current = []]
    z.map.with_index.sort.each do |x|
      if !max || max > x[0][0]
        current.push x
        max = x[0][0] + x[0][1] if !max || max < x[0][0] + x[0][1]
      else
        result.push current = [x]
        max = x[0][0] + x[0][1]
      end
    end
    result.map{ |_| _.map &:last }
  end

  module Gridable
    def rows
      Module.nesting[1].piles(map{ |n| [n.top, n.height] }).map{ |s| values_at(*s).extend Module.nesting[1]::Dumpable }
    end
    def cols
      Module.nesting[1].piles(map{ |n| [n.left, n.width] }).map{ |s| values_at(*s).extend Module.nesting[1]::Dumpable }
    end
  end

  def grid dump = nil
    logger = Module.nesting.first.logger

    all = recognize
    logger.info "all nodes: #{all.size}"
    File.write "#{dump}.all.htm", all.extend(Dumpable).dump if dump

    # adding the fields for faster upcoming computations
    struct = Struct.new *all.first.members, :midx, :midy
    all.map!{ |i| struct.new *i.values, i.left + i.width / 2.0, i.top * i.height / 2.0 }
    all = all.sort_by{ |_| [_.area, _.top, _.left] }.reverse

    rect = page.evaluate("( function(node) { return JSON.parse(JSON.stringify(node.getBoundingClientRect())) } )(arguments[0])", self)
    inside = all.reject{ |i| i.left < rect["left"] || i.left + i.width > rect["right"] || i.top < rect["top"] || i.top + i.height > rect["bottom"] }
    raise ErrorNotEnoughNodes.new "no inside nodes", all: all, inside: inside if inside.empty?
    logger.info "inside nodes: #{inside.size}"
    File.write "#{dump}.inside.htm", inside.extend(Dumpable).dump if dump
    good = inside.reject{ |i| %w{ button script svg path a img }.include? i.node.tag_name }.uniq{ |i| [i.height, i.width, i.top, i.left] }
    logger.info "good and unique: #{good.size}"   # only those that might be containers
    File.write "#{dump}.good.htm", good.extend(Dumpable).dump if dump

    # large = good#.select{ |i| i[ww] > good.map(&ww).max / 4 }
    # logger.info "large enough: #{large.size}"

    interfere = lambda do |a, b|
      a.top < b.top + b.height &&
      b.top < a.top + a.height &&
      a.left < b.left + b.width &&
      b.left < a.left + a.width
    end

    rest = good.select.with_index do |a, i|
      good.each_with_index.none? do |b, j|
        next if i == j
        a.top >= b.top && a.top + a.height <= b.top + b.height &&
        a.left >= b.left && a.left + a.width <= b.left + b.width &&
        good.all?{ |c| interfere[a, c] == interfere[b, c] }
      end
    end
    logger.info "not nested: #{rest.size}"
    File.write "#{dump}.rest.htm", rest.extend(Dumpable).dump if dump
    begin
      prev = rest.size
      rest.select!.with_index do |a, i|
        rest.each_with_index.any? do |b, j|
          cw = [[a.left + a.width, b.left + b.width].min - [a.left, b.left].max, 0].max
          i != j && !interfere[a, b] && [cw, a.width].min.fdiv(a.width) * [cw, b.width].min.fdiv(b.width) > 0.9
        end and
        rest.each_with_index.any? do |b, j|
          ch = [[a.top + a.height, b.top + b.height].min - [a.top, b.top].max, 0].max
          i != j && !interfere[a, b] && [ch, a.height].min.fdiv(a.height) * [ch, b.height].min.fdiv(b.height) > 0.9
        end
      end
    end until prev == rest.size
    logger.info "gridable: #{rest.size}"
    File.write "#{dump}.griddable.htm", rest.extend(Dumpable).dump if dump

    require "pcbr"
    pcbr = PCBR.new
    max, past = 0, []
    prev = nil
    prev_max = nil
    time = Time.now
    heuristics = %i{ SIZE AREA }
    inter = lambda do |a1, a2, b1, b2|
      c = [[a1 + a2, b1 + b2].min - [a1, b1].max, 0].max
      [c, a2].min.fdiv(a2) * [c, b2].min.fdiv(b2)
    end
    lp = lambda do |is|
      past.push is.map{ |i| 2**i }.reduce(:+)
      rest.size.times do |ij|
        next if ij <= is.last unless is.empty?
        sorted = is + [ij]
        next if pcbr.set.include? sorted
        next if is.any?{ |j| interfere[rest[ij], rest[j]] }
        sol = rest.values_at *sorted
        xn = Module.nesting.first.piles sol.map{ |s| [s.left, s.width] }
        yn = Module.nesting.first.piles sol.map{ |s| [s.top, s.height] }
        next if xn.product(yn).any?{ |i,j| (i & j).size > 1 } if sorted.size >= 4
        pcbr.store sorted, [
          *( sol.map(&:area).reduce(:+) if heuristics.include? :AREA ),
          xn.map{ |g| sosol = sol.values_at *g; next 0 if sosol.size == 1; sosol.combination(2).map{ |s1, s2| inter[s1.left, s1.width, s2.left, s2.width] }.reduce(:+) / sosol.size / (sosol.size - 1) * 2 }.reduce(:+) / xn.size,
          yn.map{ |g| sosol = sol.values_at *g; next 0 if sosol.size == 1; sosol.combination(2).map{ |s1, s2| inter[s1.top, s1.height, s2.top, s2.height] }.reduce(:+) / sosol.size / (sosol.size - 1) * 2 }.reduce(:+) / yn.size,
        ]
        if prev && Time.now - time > 3
          logger.debug "check"
          break logger.info "break 0" if Time.now - time > 30
          break logger.info "break 1" if Time.now - prev > 10
          m = pcbr.table.reject{ |i| i.first.size < 3 }.map(&:last).max
          break logger.debug "break 2" if Time.now - prev > (prev - time) * 2 && 1 == pcbr.table.count{ |i| i.last == m }
        end

        break logger.info "break 3" unless t = pcbr.table.reject{ |is,| past.include? is.map{ |i| 2**i }.reduce(:+) }.max_by(&:last)
        logger.debug [t.last, max, t.first == prev_max, t.first.map{ |i| 2**i }.reduce(:+)]
        if t.last > max && t.first != prev_max
          prev, max, prev_max = Time.now, t.last, t.first
          logger.debug [pcbr.table.size, max, t.first]
        end
        lp.call t.first
      end
    end
    lp.call []
    # TODO: if multiple with max score, take the max by area
    pcbr.table.max_by(20, &:last).each_with_index{ |_, i| logger.debug "##{i} #{_}" }
    rest.values_at(*pcbr.table.max_by(&:last).first).extend Dumpable, Gridable
  end

end

if defined? Ferrum::Frame::Runtime
  Ferrum::Node.include PageRecognizer
  Ferrum::Frame::Runtime.module_eval do
    def cyclic? object_id
      @page.command "Runtime.callFunctionOn", objectId: object_id, returnByValue: true, functionDeclaration: "function(){return false}"
    end
  end
end
