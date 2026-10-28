require "net/http"
require "json"

# "Instrutor convidado" de um curso, vindo da API externa randomuser.me.
#
# Antes o navegador chamava a API externa direto, sem nenhuma proteção.
# Agora a chamada passa pela API do CourseSphere, com tratamento de falhas:
#
#   - timeout curto: conexão 0,5 s e leitura 1,5 s;
#   - retry com backoff exponencial + jitter, só para erro transitório
#     (timeout, falha de conexão, HTTP 429/5xx), dentro de um orçamento total
#     de 3 s por requisição;
#   - circuit breaker: 5 falhas seguidas abrem o disjuntor por 30 s e as
#     chamadas seguintes falham na hora, sem prender threads do Puma;
#   - cache de 24 h por curso (Solid Cache em produção, compartilhado entre
#     as réplicas);
#   - fallback: se nada disso der certo, devolve "indisponível" e a página do
#     curso continua funcionando.
#
# Segurança: a URL é fixa e o único dado variável é o id numérico do curso
# (sem SSRF); a resposta é reduzida a nome, e-mail e foto, e a foto só é
# aceita se vier de https://randomuser.me/.
class GuestInstructorClient
  DEPENDENCY = "randomuser".freeze
  BASE_URL = "https://randomuser.me/api/".freeze
  PICTURE_PREFIX = "https://randomuser.me/".freeze

  OPEN_TIMEOUT = 0.5
  READ_TIMEOUT = 1.5
  TOTAL_BUDGET = 3.0
  MAX_ATTEMPTS = 3
  BASE_BACKOFF = 0.2
  CACHE_TTL = 24 * 60 * 60
  MAX_BODY_BYTES = 64 * 1024

  class TransientError < StandardError; end
  class PermanentError < StandardError; end

  NETWORK_ERRORS = [
    Timeout::Error, # inclui Net::OpenTimeout e Net::ReadTimeout
    Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
    SocketError, OpenSSL::SSL::SSLError, EOFError, IOError
  ].freeze

  Result = Struct.new(:instructor, :source, keyword_init: true) do
    def available?
      !instructor.nil?
    end
  end

  DEFAULT_TRANSPORT = lambda do |uri, open_timeout:, read_timeout:|
    Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                    open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: read_timeout) do |http|
      http.get(uri.request_uri, "Accept" => "application/json", "User-Agent" => "CourseSphere/1.0")
    end
  end

  @instance_mutex = Mutex.new

  class << self
    # Uma instância por processo: o disjuntor precisa enxergar todas as
    # chamadas desta réplica. Os testes trocam por uma com transporte falso.
    def instance
      @instance_mutex.synchronize { @instance ||= new }
    end

    def instance=(client)
      @instance_mutex.synchronize { @instance = client }
    end
  end

  def initialize(transport: DEFAULT_TRANSPORT, cache: nil, breaker: nil,
                 sleeper: ->(seconds) { sleep(seconds) }, random: -> { rand },
                 clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @transport = transport
    @cache = cache || Rails.cache
    @sleeper = sleeper
    @random = random
    @clock = clock
    @breaker = breaker || CircuitBreaker.new(name: DEPENDENCY, on_state_change: method(:on_state_change))
    publish_state(@breaker.state)
  end

  def state
    @breaker.state
  end

  def fetch(course_id)
    key = "guest_instructor/v1/#{Integer(course_id)}"
    cached = @cache.read(key)
    if cached
      record(:cache_hit)
      return Result.new(instructor: cached, source: :cache)
    end

    instructor = @breaker.call { request_with_retries(course_id) }
    @cache.write(key, instructor, expires_in: CACHE_TTL)
    record(:success)
    Result.new(instructor: instructor, source: :network)
  rescue CircuitBreaker::OpenError
    record(:short_circuited)
    Result.new(instructor: nil, source: :circuit_open)
  rescue StandardError => e
    record(:failure)
    log(:warn, event: "external.request_failed", error_class: e.class.name, error_message: e.message.to_s[0, 200])
    Result.new(instructor: nil, source: :error)
  end

  private

  def request_with_retries(course_id)
    deadline = @clock.call + TOTAL_BUDGET
    attempt = 0
    begin
      attempt += 1
      started = @clock.call
      response = with_hard_limit(deadline) do
        @transport.call(uri_for(course_id), open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      end
      observe_latency(@clock.call - started)
      parse!(response)
    rescue TransientError, *NETWORK_ERRORS => e
      backoff = BASE_BACKOFF * (2**(attempt - 1)) * (0.5 + @random.call) # jitter: 50% a 150%
      raise e if attempt >= MAX_ATTEMPTS || @clock.call + backoff >= deadline

      record(:retry)
      @sleeper.call(backoff)
      retry
    end
  end

  # Limite rígido por tentativa (e nunca além do orçamento total). O
  # open_timeout do Net::HTTP depende do sistema operacional: num teste com
  # um IP que não responde, o connect esperou ~21 s (timeout TCP do SO)
  # ignorando os 0,5 s configurados. Este teto garante a latência máxima
  # independentemente disso.
  def with_hard_limit(deadline, &block)
    remaining = deadline - @clock.call
    raise TransientError, "orçamento de tempo esgotado" if remaining <= 0

    Timeout.timeout([ OPEN_TIMEOUT + READ_TIMEOUT, remaining ].min, TransientError, &block)
  end

  def uri_for(course_id)
    query = URI.encode_www_form(seed: "course_#{Integer(course_id)}", inc: "name,email,picture", noinfo: "")
    URI("#{BASE_URL}?#{query}")
  end

  def parse!(response)
    code = response.code.to_i
    raise TransientError, "HTTP #{code}" if code == 429 || code >= 500
    raise PermanentError, "HTTP #{code}" unless code == 200

    body = response.body.to_s
    raise PermanentError, "resposta grande demais" if body.bytesize > MAX_BODY_BYTES

    person = JSON.parse(body).fetch("results").first
    raise PermanentError, "resposta sem resultados" unless person.is_a?(Hash)

    picture = person.dig("picture", "large").to_s
    {
      "name" => [ person.dig("name", "first"), person.dig("name", "last") ].compact.join(" ").strip[0, 100],
      "email" => person["email"].to_s[0, 200],
      "picture_url" => picture.start_with?(PICTURE_PREFIX) ? picture : nil
    }
  rescue JSON::ParserError, KeyError, NoMethodError, TypeError => e
    raise PermanentError, "resposta inválida (#{e.class})"
  end

  def on_state_change(name, from, to)
    publish_state(to)
    log(to == :open ? :warn : :info, event: "circuit_breaker.state_change", dependency: name, from: from, to: to)
  end

  def publish_state(state)
    Observability::Metrics::CIRCUIT_BREAKER_STATE.set(CircuitBreaker::STATES.fetch(state), labels: { dependency: DEPENDENCY })
  rescue StandardError
    nil
  end

  def record(outcome)
    Observability::Metrics::EXTERNAL_REQUESTS.increment(labels: { dependency: DEPENDENCY, outcome: outcome.to_s })
  rescue StandardError
    nil
  end

  def observe_latency(seconds)
    Observability::Metrics::EXTERNAL_DURATION.observe(seconds, labels: { dependency: DEPENDENCY })
  rescue StandardError
    nil
  end

  def log(level, **payload)
    Rails.logger&.public_send(level, payload)
  rescue StandardError
    nil
  end
end
