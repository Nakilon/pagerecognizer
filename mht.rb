# https://datatracker.ietf.org/doc/html/rfc2557
# https://en.wikipedia.org/wiki/Quoted-printable

# install cwebp and gem "oga"

require "strscan"
mht = ARGF.read
scanner = StringScanner.new mht
fail unless scanner.scan(/\AFrom: <Saved by Blink>\r
Snapshot-Content-Location: \S+\r
Subject: \S+\r
Date: [A-Z][a-z][a-z], \d\d? [A-Z][a-z][a-z] 20\d\d \d\d:\d\d:\d\d -0000\r
MIME-Version: 1\.0\r
Content-Type: multipart\/related;\r
\ttype="text\/html";\r
\tboundary="(----MultipartBoundary--[a-zA-Z0-9]{42}----)"\r\n\r\n\r\n--\1/)
delimeter = scanner[1]
fail unless scanner.charpos == prev = scanner.pos
reps = []
htmls = ""
while s = scanner.search_full(Regexp.new(delimeter), true, true)
  doc = s[0...-delimeter.size-4]
  case doc
  when /\A\r\nContent-Type: text\/html\r
Content-ID: <frame-[A-Z0-9]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: chrome-error:\/\/chromewebdata\/\r\n\r\n/,
       /\A\r\nContent-Type: text\/html\r
Content-ID: <frame-[A-Z0-9]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: quoted-printable\r\n\r\n/
    puts "trash #{$'.size}"
    reps.push [prev-delimeter.size-2, scanner.pos-delimeter.size-4, "", ""]
  when /\A\r\nContent-Type: text\/html\r
Content-ID: <frame-[A-Z0-9]{32}@mhtml\.blink>\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: \S+\r\n\r\n/
    puts "html #{$'.size}"
    header = $&
    t = $'.gsub(/=(..)/){ fail $1 unless "3D" == $1 || "20" == $1 unless "80" <= $1 && $1 <= "F0"; $1.hex.chr }.gsub("=\r\n", "")
    puts "unpacked #{t.size}"
    require "oga"
    html = Oga.parse_html t.force_encoding "utf-8"

    puts "Oga.to_s #{html.to_s.size}"
    html.xpath("//*[not(*)]").group_by(&:name).
      map{ |_, g| [_, g.map(&:to_s).map(&:size).reduce(:+)] }.
      sort_by(&:last).reverse.take(5).each &method(:p)

    5.times do
      html_to_s = html.to_s
      html.xpath("//svg/defs/g[not(.//g[@id])]").group_by{ |_| _["id"] }.each do |id, g|
        fail id unless id.count("^a-z0-9_-").zero?
        s = html_to_s.scan(/[^a-z0-9_-]#{id}[^a-z0-9_-]/).size
        fail if g.size > s
        g.each &:remove if g.size == s
      end
      puts "defs/g #{html.to_s.size}"
    end
    html.xpath("//svg/defs/text()").each{ |_| _.remove if "\r\n" == _.text }
    puts "defs/text() #{html.to_s.size}"

    html.xpath("//*[not(*)]").group_by(&:name).
      map{ |_, g| [_, g.map(&:to_s).map(&:size).reduce(:+)] }.
      sort_by(&:last).reverse.take(5).each &method(:p)

    htmls.concat html.to_s.force_encoding("utf-8").downcase
    reps.push [prev, scanner.pos-delimeter.size-4, header, html.to_s, true]
  when /\A\r\nContent-Type: text\/css\r
Content-Transfer-Encoding: quoted-printable\r
Content-Location: \S+\r\n\r\n/
    puts "css #{$'.size}"
    header = $&
    css = $'.gsub(/=(..)/){ fail $1 unless "3D" == $1 || "20" == $1 unless "80" <= $1 && $1 <= "F0"; $1.hex.chr }.gsub("=\r\n", "")
    puts "unpacked #{css.size}"
    css.gsub!(/^[^\r\n,:@*%~{]+\{[^}]+\}/) do |line|
      case line
      when /\A\s* (
                    [a-z\d_-]* (
                                [.#][a-z\d_-]+|
                                               \[[a-z\d_-]+(="[a-z\d_\#-]+")?\]
                                                                      )*
                                                                         (
                                                                          (\ |\ >\ |\ ~\ |\ \+\ )
                                                                                                  [a-z\d_-]* (
                                                                                                              [.#][a-z\d_-]+|
                                                                                                                             \[[a-z\d_-]+(="[a-z\d_\#-]+")?\]
                                                                                                                                                    )*
                                                                                                                                                      )*
                                                                                                                                                         )\s*\{[^}]+\}\z/xi
        line unless $1.scan(/[a-z\d_-]+/).any? do |t|
          1 > htmls.scan(t.downcase).size
        end
      else
        fail line.inspect
      end
    end
    css.gsub!(/[\r\n]+/, "\n")
    puts "css #{css.size}"
    reps.push [prev, scanner.pos-delimeter.size-4, header, css, true]
  when /\A\r\nContent-Type: image\/(webp|png|gif)\r
Content-Transfer-Encoding: base64\r
Content-Location: \S+\r\n\r\n/
    puts "#{$1} #{$'.size}"
    header = $&
    require "base64"
    File.binwrite "temp.#{$1}", Base64.decode64($')
    require "open3"
    string, status = Open3.capture2e "cwebp -quiet -sharp_yuv -m 6 -q 0 -alpha_q 0 temp.#{$1} -o -"
    fail unless status.exitstatus.zero?
    string = Base64.encode64 string
    puts "cwebp #{string.size}"
    reps.push [prev, scanner.pos-delimeter.size-4, header, string]
  else
    puts doc[0..300]
    fail
  end
  fail unless scanner.charpos == prev = scanner.pos
end
reps.reverse_each do |from, to, header, str, qp|
  str = qp ?
    header + str.gsub("=", "=3D").
      b.gsub(/[\x80-\xF0]/n){ |_| "=%02X" % _.ord }.
      gsub(/.{73}[^=][^=](?=.)/, "\\0=\r\n") :
    header + str.gsub("\n", "\r\n")
  p [str.size, "to - from = #{to - from}"]
  mht[from...to] = str
end
p File.write "temp.mht", mht
