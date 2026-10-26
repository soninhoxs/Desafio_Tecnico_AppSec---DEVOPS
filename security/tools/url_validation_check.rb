require "uri"
def ok?(v)
  u = URI.parse(v)
  u.is_a?(URI::HTTP) && %w[http https].include?(u.scheme.to_s.downcase) && u.host.to_s.include?(".") && u.userinfo.nil?
rescue URI::InvalidURIError
  false
end
old = URI::DEFAULT_PARSER.make_regexp
["javascript:alert(document.domain)","JaVaScRiPt:alert(1)","data:text/html,<script>alert(1)</script>","vbscript:msgbox(1)","texto qualquer http://exemplo.com","ftp://exemplo.com/video.mp4","https://usuario:senha@exemplo.com/video","https://localhost/video","nao-e-url","https://youtube.com/watch?v=abc123","https://www.youtube.com","HTTPS://WWW.YOUTUBE.COM/x"].each do |v|
  printf "%-45s antigo=%-5s novo=%s\n", v, (v =~ old ? "ACEITA" : "rejeita"), ok?(v) ? "ACEITA" : "rejeita"
end
