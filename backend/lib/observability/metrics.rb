module Observability
  # Métricas expostas em GET /metrics (formato de texto do Prometheus).
  #
  # Uma réplica = um processo Puma (WEB_CONCURRENCY=1, só threads), então o
  # store em memória do prometheus-client é suficiente. Escala-se com mais
  # réplicas (compose/k8s), e o Prometheus soma as séries de cada uma.
  module Metrics
    REGISTRY = Prometheus::Client::Registry.new

    LATENCY_BUCKETS = [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 ].freeze

    HTTP_REQUESTS = REGISTRY.counter(
      :http_server_requests_total,
      docstring: "Requisições HTTP atendidas, por método, rota (padrão Rails) e status.",
      labels: %i[method route status]
    )

    HTTP_DURATION = REGISTRY.histogram(
      :http_server_request_duration_seconds,
      docstring: "Latência das requisições HTTP em segundos.",
      labels: %i[method route],
      buckets: LATENCY_BUCKETS
    )

    HTTP_IN_FLIGHT = REGISTRY.gauge(
      :http_server_requests_in_flight,
      docstring: "Requisições em andamento nesta réplica."
    )

    SECURITY_EVENTS = REGISTRY.counter(
      :coursesphere_security_events_total,
      docstring: "Eventos de segurança (login, bloqueio, rate limit, token recusado, acesso negado...).",
      labels: %i[event]
    )

    DB_POOL = REGISTRY.gauge(
      :coursesphere_db_pool_connections,
      docstring: "Conexões do pool do ActiveRecord por estado.",
      labels: %i[state]
    )

    APP_INFO = REGISTRY.gauge(
      :coursesphere_app_info,
      docstring: "Versão e instância em execução (valor sempre 1).",
      labels: %i[version instance]
    )

    UPTIME = REGISTRY.gauge(:coursesphere_uptime_seconds, docstring: "Segundos desde o boot desta réplica.")

    # Dependências externas (ex.: randomuser.me) — ver GuestInstructorClient.
    EXTERNAL_REQUESTS = REGISTRY.counter(
      :coursesphere_external_requests_total,
      docstring: "Chamadas a dependências externas por resultado " \
                 "(success, retry, failure, short_circuited, cache_hit).",
      labels: %i[dependency outcome]
    )

    EXTERNAL_DURATION = REGISTRY.histogram(
      :coursesphere_external_request_duration_seconds,
      docstring: "Latência de cada tentativa de chamada a uma dependência externa.",
      labels: %i[dependency],
      buckets: [ 0.05, 0.1, 0.25, 0.5, 1, 1.5, 2, 3 ]
    )

    CIRCUIT_BREAKER_STATE = REGISTRY.gauge(
      :coursesphere_circuit_breaker_state,
      docstring: "Estado do circuit breaker por dependência: 0 = fechado, 1 = meio-aberto, 2 = aberto.",
      labels: %i[dependency]
    )

    # As séries das dependências conhecidas nascem em zero no boot. Sem isso, o
    # disjuntor só aparece no Prometheus depois da primeira troca de estado, e
    # cada resultado só depois da primeira ocorrência: o painel e o alerta
    # ficariam "sem dado" em vez de mostrar fechado / zero.
    EXTERNAL_DEPENDENCIES = %w[randomuser].freeze # GuestInstructorClient::DEPENDENCY
    EXTERNAL_OUTCOMES = %w[success retry failure short_circuited cache_hit].freeze

    EXTERNAL_DEPENDENCIES.each do |dependency|
      CIRCUIT_BREAKER_STATE.init_label_set(dependency: dependency)
      EXTERNAL_DURATION.init_label_set(dependency: dependency)
      EXTERNAL_OUTCOMES.each do |outcome|
        EXTERNAL_REQUESTS.init_label_set(dependency: dependency, outcome: outcome)
      end
    end

    def self.render
      collect_runtime_gauges
      Prometheus::Client::Formats::Text.marshal(REGISTRY)
    end

    def self.collect_runtime_gauges
      APP_INFO.set(1, labels: { version: Observability.app_version, instance: Observability.instance_id })
      UPTIME.set(Observability.uptime_seconds)

      return unless defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?

      stat = ActiveRecord::Base.connection_pool.stat
      %i[size busy idle waiting dead].each do |state|
        DB_POOL.set(stat[state].to_i, labels: { state: state.to_s })
      end
    rescue StandardError
      # Coletar métricas nunca deve derrubar o /metrics.
      nil
    end
  end
end
