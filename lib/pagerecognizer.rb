Ferrum::Frame::Runtime.module_eval do
  def cyclic? object_id
    @page.command "Runtime.callFunctionOn", objectId: object_id, returnByValue: true, functionDeclaration: "function(){return false}"
  end
end if defined? Ferrum::Frame::Runtime


module PageRecognizer

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

  def recognize logger = nil
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
        logger.info "#{nodes.size} DOM nodes found" if logger
      end
    end
    logger.info "#{nodes.size} DOM nodes found" if logger

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

  private def recognize_more logger = nil
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
        logger.info "#{nodes.size} DOM nodes found" if logger
      end
    end
    logger.info "#{nodes.size} DOM nodes found" if logger

    nodes.reject!{ |i| i.height.zero? || i.width.zero? }
    nodes
  end

  private def split hh, ww, tt, logger = nil
    logger ||= Object.new.tap do |stub|
      stub.define_singleton_method(:info){|*|}
      stub.define_singleton_method(:debug){|*|}
    end

    nodes = nil
    try = lambda do
      nodes = recognize_more
      logger.info "nodes: #{nodes.size}"
      nodes.reject!{ |i| %w{ button script svg path a img span }.include? i.node.tag_name }
    end
    unless defined? Selenium::WebDriver::Error::StaleElementReferenceError
      try.call
    else
      t = Time.now
      begin
        try.call
      rescue Selenium::WebDriver::Error::StaleElementReferenceError
        raise if Time.now > t + 10
        retry
      end
    end
    logger.debug "good nodes: #{nodes.size}"

    # euristic:
    # when we split vertically   we exclude nodes with width  is much smaller than maximal
    # when we split horizontally we exclude nodes with height is much smaller than maximal
    nodes.select!{ |i| i[ww] > nodes.map(&ww).max / 3 }
    logger.debug "large enough: #{nodes.size}"

    # when we split vertically it detects if nodes have common horizontal lines
    # when we split horizontally it detects if nodes have common vertical lines
    interfere = lambda do |a, b|
      d = a[tt] - b[tt]
      d < b[hh] && b[tt] < a[tt] + a[hh]
    end

    # indexes of nodes that are within another node having the same set of interfering nodes
    nested = nodes.each_with_index.to_a.combination(2).map do |(a, i), (b, j)|
      i if a[ww] <= b[ww] && a[tt] >= b[tt] && a[tt] + a[hh] <= b[tt] + b[hh] &&  # a is inside b
           nodes.map.with_index{ |e, i| i if interfere[a, e] } ==
           nodes.map.with_index{ |e, i| i if interfere[b, e] }
    end.compact.uniq
    logger.debug "nested: #{nested.size}"

    # adding the :area field for faster upcoming computations
    struct = Struct.new *nodes.first.members, :area
    nodes.map!{ |i| struct.new *i.values, i.width * i.height }

    # nodes that are not nested
    rest = nodes.select.with_index{ |_, k| not nested.include? k }.sort_by(&tt)
    logger.info "not nested: #{rest.size}"
    # rest = rest.sample 50

    memo = rest.map{ [] }
    memoized_interfere = lambda do |aa, bb|
      aa, bb = bb, aa if aa > bb
      next memo[aa][bb] unless memo[aa][bb].nil?
      memo[aa][bb] = interfere.call rest[aa], rest[bb]
    end

    max = 0
    prev = Time.now - 2
    ff = lambda do |acc = [], drop = 0, is = [], area_acc = 0|
      # if Time.now > prev + 1
        prev = Time.now
      # end
      b = nil
      stop = false
      t = rest.drop(drop).flat_map.with_index do |e, i|
          next if stop
          next if is.any?{ |j| memoized_interfere[j, i + drop] } ##&& b.any?{ |c| interfere[c, e] }
          if b && !interfere[b, e]
            stop = true
            next
          end
          b ||= e
          ff.call([*acc, e], drop + i+1, [*is, drop + i], area_acc + e.area)
      end.compact
      t = [[acc, area_acc]] if t.empty?   # why not always include this solution?
      t.each do |sol, area|
        logger.info "max=#{max = area}" if area > max
      end
    end
    # require "ruby-prof"
    # RubyProf.start
    time = Time.now
    solutions = ff.call
    logger.info "#{Time.now - time} sec"
    logger.info "#{solutions.size} solutions"
    # result = RubyProf.stop
    # RubyProf::FlatPrinter.new(result).print STDOUT

    # logger.debug solutions.map(&:first).map(&:size)
    grouped = solutions.reject{ |(solution, area)| solution.size == 1 }.
                        sort_by(&:last).reverse.group_by{ |subset, area| subset.size }.
                        map{ |k, g| [k, g.take(10)] }
    fr = grouped.flat_map(&:last)     # because destructive `reject!` iteration
    # fail "the next line may fail on the calling the `#last` method" if rest == 1
    best = grouped.each{ |size, group| logger.debug [size, group.map(&:last).take(10)] }.
                   each{ |k,g| g.reject!{ |(solution, area)| fr.any?{ |sol, ar| ar >= area && sol.size > solution.size } } }.
                   reject{ |size, group| group.empty? }.
                   each{ |size, group| logger.info [size, group.map(&:last).take(10)].inspect }.
                   first.last.map(&:first)

    best.first.extend Dumpable
  end

  def rows
    split :height, :width, :top
  end
  def cols
    split :width, :height, :left
  end

end
