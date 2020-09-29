module PageRecognizer
  class << self
    attr_accessor :logger
  end
  require "logger"
  self.logger = Logger.new STDOUT

  module Dumpable
    def dump
      "<html><body>#{
        map.with_index do |n, i|
          "<div style='position: absolute; background-color: hsla(#{
            360 * i / size
          },100%,50%,0.5); top: #{n.top}; left: #{n.left}; width: #{n.width}; height: #{n.height}'>#{
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

  def recognize
    logger = Module.nesting.first.logger

    nodes = []
    try = lambda do
      prev = nodes
      code = "( function(node) {
        var x = scrollX, y = scrollY;
        var _tap = function(x, f){ f(); return x };
        var f = function(node) {
          node.scrollIntoView();
          var rect = JSON.parse(JSON.stringify(node.getBoundingClientRect()));
          var child_nodes = Array.from(node.childNodes).filter(function(node) { return node.nodeType == 1 });
          var clickable;
          if (node.nodeName == 'svg') {
            var states = child_nodes.map( function(n){
              return _tap(n.style ? n.style.display : '', function(){ n.style.display = 'none' } );
            } );
            clickable = (node === document.elementFromPoint(rect.x + rect.width/2, rect.y + rect.height/2));
            var _zip = function(a, b){ return a.map( function(e, i) { return [e, b[i]] } ) };
            _zip(child_nodes, states).forEach( function(_){ _[0].style.display = _[1] } );
          } else {
            clickable = (node === document.elementFromPoint(rect.x + rect.width/2, rect.y + rect.height/2));
          };
          rect.top += scrollY;
          rect.left += scrollX;
          return [ [
            rect.top, rect.left, rect.width, rect.height, clickable, node
          ] ].concat(node.nodeName == 'svg' ? [] : child_nodes.flatMap(f));
        };
        return _tap(f(node), function(){ scrollTo(x, y) });
      } )(arguments[0])"
      str = Struct.new :top, :left, :width, :height, :clickable, :node
      nodes = page.evaluate(code, self).map{ |s| str.new *s }
      nodes.size == prev.size
    end

    if defined? Selenium::WebDriver::Wait
      Selenium::WebDriver::Wait.new(
        message: "number of DOM elements didn't stop to change"
      ).until &try
    else
      t = Time.now
      until try.call
        fail "number of DOM elements didn't stop to change" if Time.now > t + 5
      end
    end
    logger.info "#{nodes.size} DOM nodes found"

    nodes.select! &:clickable
    nodes.reject do |n|
      nodes.any? do |nn|
        cs = [
          nn.top <=> n.top,
          nn.left <=> n.left,
          n.left + n.width <=> nn.left + nn.width,
          n.top + n.height <=> nn.top + nn.height,
        ]
        cs.include?(1) && !cs.include?(-1)
      end
    end.extend Dumpable
  end

  private def recognize_more
    logger = Module.nesting.first.logger

    nodes = []
    try = lambda do
      prev = nodes
      code = "( function(node) {
        var x = scrollX, y = scrollY;
        var _tap = function(x, f){ f(); return x };
        var f = function(node) {
          node.scrollIntoView();
          var rect = JSON.parse(JSON.stringify(node.getBoundingClientRect()));
          rect.top += scrollY;
          rect.left += scrollX;
          return [ [
            node, JSON.stringify([rect.top, rect.left, rect.width, rect.height])
          ] ].concat(Array.from(node.childNodes).filter(function(node) { return node.nodeType == 1 }).flatMap(f));
        };
        return _tap(f(node), function(){ scrollTo(x, y) });
      } )(arguments[0])"
      str = Struct.new :node, :top, :left, :width, :height
      nodes = page.evaluate(code, self).map{ |node, a| str.new node, *JSON.load(a) }
      nodes.size == prev.size
    end

    if defined? Selenium::WebDriver::Wait
      Selenium::WebDriver::Wait.new(
        message: "number of DOM elements didn't stop to change"
      ).until &try
    else
      t = Time.now
      until try.call
        fail "number of DOM elements didn't stop to change" if Time.now > t + 10
      end
    end
    logger.info "#{nodes.size} DOM nodes found"

    nodes.reject!{ |i| i.height.zero? || i.width.zero? }
    nodes
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

  private def split heuristics, hh, ww, tt, ll
    logger = Module.nesting.first.logger

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
    all = unstale.call do recognize_more end.sort_by(&tt)
    logger.info "all nodes: #{all.size}"
    rect = page.evaluate("( function(node) { return JSON.parse(JSON.stringify(node.getBoundingClientRect())) } )(arguments[0])", self)
    inside = all.reject{ |i| i.left < rect["left"] || i.left + i.width > rect["right"] || i.top < rect["top"] || i.top + i.height > rect["bottom"] }
    raise ErrorNotEnoughNodes.new "no inside nodes", all: all, inside: inside if inside.empty?
    logger.info "inside nodes: #{inside.size}"
    nodes = unstale.call do inside.reject{ |i| %w{ button script svg path a img span }.include? i.node.tag_name } end.uniq{ |i| [i[hh], i[ww], i[tt], i[ll]] }
    logger.info "good and unique: #{nodes.size}"   # only those that might be containers

    large = nodes#.select{ |i| i[ww] > nodes.map(&ww).max / 4 }
    logger.info "large enough: #{large.size}"

    interfere = lambda do |a, b|
      a[tt] < b[tt] + b[hh] &&
      b[tt] < a[tt] + a[hh]
    end

    rest = large.select.with_index do |a, i|
      large.each_with_index.none? do |b, j|
        next if i == j
        a[tt] >= b[tt] && a[tt] + a[hh] <= b[tt] + b[hh] &&
        large.all?{ |c| interfere[a, c] == interfere[b, c] }
      end
    end
    logger.info "not nested: #{rest.size}"
    # rest = rest.sample 50

    # adding the :area field for faster upcoming computations
    struct = Struct.new *large.first.members, :area
    rest.map!{ |i| struct.new *i.values, i.width * i.height }

    require "pcbr"
    pcbr = PCBR.new
    is = []
    max, past = 0, []
    prev = nil
    time = Time.now
    loop do
      rest.each_with_index do |node, i|
        next if is.any?{ |j| i == j || interfere[rest[i], rest[j]] }
        sol = rest.values_at *is, i
        pcbr.store [*is, i].sort, [
          *( is.size                                                                                                                if heuristics.include? :SIZE   ),
          *( sol.map(&:area).inject(:+)                                                                                             if heuristics.include? :AREA   ),
          # https://en.wikipedia.org/wiki/Mean_absolute_difference
          *( -sol.product(sol).map{ |s1, s2| (s1.width              - s2.width             ).abs }.inject(:+) / sol.size / sol.size if heuristics.include? :WIDTH  ),
          *( -sol.product(sol).map{ |s1, s2| (s1.height             - s2.height            ).abs }.inject(:+) / sol.size / sol.size if heuristics.include? :HEIGHT ),
          *( -sol.product(sol).map{ |s1, s2| (s1[ll] + s1[ww] / 2.0 - s2[ll] - s2[ww] / 2.0).abs }.inject(:+) / sol.size / sol.size if heuristics.include? :MIDDLE ),
        ] unless pcbr.set.include? [*is, i].sort
      end
      if prev && Time.now - time > 1 && (Time.now - prev > (prev - time))
        m = pcbr.table.reject{ |i| i.first.size < 2 }.map(&:last).max
        break if 1 == pcbr.table.count{ |i| i.last == m } || Time.now - time > 5
      end
      break unless t = pcbr.table.reject{ |is,| past.include? is.map{ |i| 2**i }.inject(:+) }.max_by(&:last)
      if t.last > max
        prev, max = Time.now, t.last
        logger.debug [Time.now - time, max, t.first]
      end
      past.push (is = t.first).map{ |i| 2**i }.inject(:+)
    end
    # TODO: if multiple with max score, take the max by area
    unless best = pcbr.table.reject{ |is,| is.size < 2 }.max_by(&:last)
      raise ErrorNotEnoughNodes.new "failed to split <#{tag_name}>", all: all, inside: inside, nodes: nodes, large: large, rest: rest
    end
    rest.values_at(*best.first).extend(Dumpable)
  end

  def rows *heuristics
    heuristics = %i{ AREA HEIGHT WIDTH } if heuristics.empty?
    split heuristics, :height, :width, :top, :left
  end
  def cols *heuristics
    heuristics = %i{ AREA HEIGHT WIDTH } if heuristics.empty?
    split heuristics, :width, :height, :left, :top
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

  def grid
    logger = Module.nesting.first.logger

    all = recognize_more
    logger.info "all nodes: #{all.size}"

    # adding the :area field for faster upcoming computations
    struct = Struct.new *all.first.members, :area, :midx, :midy
    all.map!{ |i| struct.new *i.values, i.width * i.height, i.left + i.width / 2.0, i.top * i.height / 2.0 }
    all = all.sort_by{ |_| [_.area, _.top, _.left] }.reverse

    rect = page.evaluate("( function(node) { return JSON.parse(JSON.stringify(node.getBoundingClientRect())) } )(arguments[0])", self)
    inside = all.reject{ |i| i.left < rect["left"] || i.left + i.width > rect["right"] || i.top < rect["top"] || i.top + i.height > rect["bottom"] }
    raise ErrorNotEnoughNodes.new "no inside nodes", all: all, inside: inside if inside.empty?
    logger.info "inside nodes: #{inside.size}"
    nodes = inside.reject{ |i| %w{ button script svg path a img span }.include? i.node.tag_name }.uniq{ |i| [i.height, i.width, i.top, i.left] }
    logger.info "good and unique: #{nodes.size}"   # only those that might be containers

    large = nodes
    logger.info "large enough: #{large.size}"

    interfere = lambda do |a, b|
      a.top < b.top + b.height &&
      b.top < a.top + a.height &&
      a.left < b.left + b.width &&
      b.left < a.left + a.width
    end

    rest = large.select.with_index do |a, i|
      large.each_with_index.none? do |b, j|
        next if i == j
        a.top >= b.top && a.top + a.height <= b.top + b.height &&
        a.left >= b.left && a.left + a.width <= b.left + b.width &&
        large.all?{ |c| interfere[a, c] == interfere[b, c] }
      end
    end
    logger.info "not nested: #{rest.size}"
    3.times do  # TODO: until it stops shrinking
      rest = rest.select.with_index do |a, i|
        rest.each_with_index.any? do |b, j|
          cw = [[a.left + a.width, b.left + b.width].min - [a.left, b.left].max, 0].max
          i != j && !interfere[a, b] && [cw, a.width].min.fdiv(a.width) * [cw, b.width].min.fdiv(b.width) > 0.9
        end and
        rest.each_with_index.any? do |b, j|
          ch = [[a.top + a.height, b.top + b.height].min - [a.top, b.top].max, 0].max
          i != j && !interfere[a, b] && [ch, a.height].min.fdiv(a.height) * [ch, b.height].min.fdiv(b.height) > 0.9
        end
      end
      rest = rest.select.with_index do |a, i|
        rest.each_with_index.any? do |b, j|
          cw = [[a.left + a.width, b.left + b.width].min - [a.left, b.left].max, 0].max
          i != j && !interfere[a, b] && [cw, a.width].min.fdiv(a.width) * [cw, b.width].min.fdiv(b.width) > 0.9
        end and
        rest.each_with_index.any? do |b, j|
          ch = [[a.top + a.height, b.top + b.height].min - [a.top, b.top].max, 0].max
          i != j && !interfere[a, b] && [ch, a.height].min.fdiv(a.height) * [ch, b.height].min.fdiv(b.height) > 0.9
        end
      end
    end
    logger.info "gridable: #{rest.size}"

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
      [*rest.size.times.zip].each do |ij|
        next if ij.min <= is.max unless is.empty?
        sorted = (is + ij).sort
        next if pcbr.set.include? sorted
        next if ij.product(is).any?{ |i,j| interfere[rest[i], rest[j]] }
        sol = rest.values_at *sorted
        xn = Module.nesting.first.piles sol.map{ |s| [s.left, s.width] }
        yn = Module.nesting.first.piles sol.map{ |s| [s.top, s.height] }
        if sorted.size >= 4
          next if xn.product(yn).any?{ |i,j| (i & j).size > 1 }
        end
        pcbr.store sorted, [
          *( sol.map(&:area).inject(:+) if heuristics.include? :AREA ),
          xn.size * yn.size,
          xn.map{ |g| sosol = rest.values_at *g; next 0 if sosol.size == 1; sosol.combination(2).map{ |s1, s2| inter[s1.left, s1.width, s2.left, s2.width] }.inject(:+) / sosol.size / (sosol.size - 1) * 2 }.inject(:+) / xn.size,
          yn.map{ |g| sosol = rest.values_at *g; next 0 if sosol.size == 1; sosol.combination(2).map{ |s1, s2| inter[s1.top, s1.height, s2.top, s2.height] }.inject(:+) / sosol.size / (sosol.size - 1) * 2 }.inject(:+) / yn.size,
        ]
        if prev && Time.now - time > 1 && (Time.now - prev > (prev - time) * 2 || Time.now - prev > 3)
          m = pcbr.table.reject{ |i| i.first.size < 3 }.map(&:last).max
          break if 1 == pcbr.table.count{ |i| i.last == m } || Time.now - time > 3
        end
        break unless t = pcbr.table.reject{ |is,| past.include? is.map{ |i| 2**i }.inject(:+) }.max_by(&:last)  # why reject?!
        past.push is.map{ |i| 2**i }.inject(:+)
        if t.last > max && (!prev_max || t.first != prev_max)
          prev, max, prev_max = Time.now, t.last, t.first
          logger.debug [pcbr.table.size, max, t.first]
        end
        lp.call t.first
      end
    end
    lp.call []
    # TODO: if multiple with max score, take the max by area
    rest.values_at(*pcbr.table.max_by(&:last).first).extend(Dumpable)
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
