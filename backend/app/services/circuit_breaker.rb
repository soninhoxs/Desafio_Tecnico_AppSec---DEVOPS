# Disjuntor (circuit breaker) para dependências externas.
#
#   fechado     -> as chamadas passam; N falhas seguidas abrem o disjuntor
#   aberto      -> as chamadas falham na hora, sem tocar na rede, até o cooldown
#   meio-aberto -> depois do cooldown, UMA chamada de teste passa:
#                  sucesso fecha o disjuntor, falha reabre
#
# Sem isso, uma dependência lenta ou fora do ar prende threads do Puma em
# timeouts repetidos e derruba a latência da API inteira (falha em cascata).
#
# O estado é por processo (cada réplica tem o seu disjuntor) e protegido por
# Mutex, porque o Puma atende requisições em várias threads.
class CircuitBreaker
  class OpenError < StandardError; end

  STATES = { closed: 0, half_open: 1, open: 2 }.freeze

  attr_reader :name

  def initialize(name:, failure_threshold: 5, cooldown: 30,
                 clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                 on_state_change: nil)
    @name = name
    @failure_threshold = failure_threshold
    @cooldown = cooldown
    @clock = clock
    @on_state_change = on_state_change
    @mutex = Mutex.new
    @state = :closed
    @failures = 0
    @opened_at = nil
    @trial_in_flight = false
  end

  def state
    @mutex.synchronize { current_state }
  end

  # Executa o bloco se o disjuntor permitir. Uma exceção do bloco conta como
  # falha e é propagada. Com o disjuntor aberto, levanta OpenError sem
  # executar o bloco.
  def call
    acquire!
    begin
      result = yield
    rescue StandardError
      record_failure
      raise
    end
    record_success
    result
  end

  private

  # Chamar só com o mutex adquirido.
  def current_state
    transition(:half_open) if @state == :open && @clock.call - @opened_at >= @cooldown
    @state
  end

  def acquire!
    @mutex.synchronize do
      case current_state
      when :open
        raise OpenError, "circuit #{name} is open"
      when :half_open
        # Só uma chamada de teste por vez; as outras continuam falhando rápido.
        raise OpenError, "circuit #{name} is half-open (trial in progress)" if @trial_in_flight

        @trial_in_flight = true
      end
    end
  end

  def record_success
    @mutex.synchronize do
      @trial_in_flight = false
      @failures = 0
      transition(:closed)
    end
  end

  def record_failure
    @mutex.synchronize do
      @trial_in_flight = false
      @failures += 1
      if @state == :half_open || @failures >= @failure_threshold
        @opened_at = @clock.call
        @failures = 0
        transition(:open)
      end
    end
  end

  def transition(new_state)
    return if new_state == @state

    old_state = @state
    @state = new_state
    @on_state_change&.call(name, old_state, new_state)
  end
end
