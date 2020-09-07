Ferrum::Frame::Runtime.module_eval do
  def cyclic? object_id
    @page.command "Runtime.callFunctionOn", objectId: object_id, returnByValue: true, functionDeclaration: "function(){return false}"
  end
end if defined? Ferrum::Frame::Runtime


module PageRecognizer

  module Items
    def visualize
      "<html><body>#{
        map.with_index do |n, i|
          "<div style='position: absolute; background-color: hsla(#{
            360 * i / size
          },100%,50%,0.5); left: #{n.left}; top: #{n.top}; width: #{n.width}; height: #{n.height}'>#{
            n.node.tag_name.upcase
          }</div>"
        end.join
      }</body></html>"
    end
  end

  def recognize logger = nil
    flat = []
    try = lambda do
      prev = flat
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
          var qwe = false;
          var asd;
          return [ [
            rect.top, rect.left, rect.width, rect.height, clickable, node
          ] ].concat(node.nodeName == 'svg' ? [] : child_nodes.flatMap(f));
        };
        return _tap(f(node), function(){ scrollTo(x, y) });
      } )(arguments[0])"
      str = Struct.new :top, :left, :width, :height, :clickable, :node
      flat = page.evaluate(code, self).map{ |s| str.new *s }
      flat.size == prev.size
    end
    if defined? Selenium::WebDriver
      Selenium::WebDriver::Wait.new(
        message: "number of DOM elements didn't stop to change"
      ).until &try
    else
      t = Time.now
      until try.call
        fail "number of DOM elements didn't stop to change" if Time.now > t + 5
        logger.info "#{flat.size} DOM nodes found" if logger
      end
    end
    logger.info "#{flat.size} DOM nodes found" if logger

    flat.select! &:clickable
    flat.reject do |n|
      flat.any? do |nn|
        cs = [
          nn.top <=> n.top,
          nn.left <=> n.left,
          n.left + n.width <=> nn.left + nn.width,
          n.top + n.height <=> nn.top + nn.height,
        ]
        cs.include?(1) && !cs.include?(-1)
      end
    end.extend Items
  end

end
