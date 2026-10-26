# Evidência da VULN-06: compara a validação ANTIGA de video_url
# (URI::DEFAULT_PARSER.make_regexp) com a NOVA (URI.parse + allowlist http/https).
#
#   ruby security/tools/url_validation_check.rb
require "uri"

def new_validation_accepts?(value)
  uri = URI.parse(value)
  uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme.to_s.downcase) &&
    uri.host.to_s.include?(".") && uri.userinfo.nil?
rescue URI::InvalidURIError
  false
end

# Reproduz a validação antiga, de propósito, só para comparar com a nova.
# A regex não tem âncora: é exatamente a falha da VULN-06. Não é código da API.
OLD_REGEX = URI::DEFAULT_PARSER.make_regexp # nosemgrep: security.semgrep.unanchored-uri-regexp-validation

SAMPLES = [
  "javascript:alert(document.domain)",
  "JaVaScRiPt:alert(1)",
  "data:text/html,<script>alert(1)</script>",
  "vbscript:msgbox(1)",
  "texto qualquer http://exemplo.com",
  "ftp://exemplo.com/video.mp4",
  "https://usuario:senha@exemplo.com/video",
  "https://localhost/video",
  "nao-e-url",
  "https://youtube.com/watch?v=abc123",
  "https://www.youtube.com",
  "HTTPS://WWW.YOUTUBE.COM/x"
].freeze

SAMPLES.each do |value|
  old = value.match?(OLD_REGEX) ? "ACEITA" : "rejeita"
  new = new_validation_accepts?(value) ? "ACEITA" : "rejeita"
  printf "%-45s antigo=%-7s novo=%s\n", value, old, new
end
