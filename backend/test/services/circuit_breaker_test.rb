require "test_helper"

# Tratamento de falhas: estados do circuit breaker com relógio controlado.
class CircuitBreakerTest < ActiveSupport::TestCase
  def setup
    @now = 0.0
    @changes = []
    @breaker = CircuitBreaker.new(
      name: "teste", failure_threshold: 3, cooldown: 30,
      clock: -> { @now },
      on_state_change: ->(_name, from, to) { @changes << [ from, to ] }
    )
  end

  def fail_once
    @breaker.call { raise IOError, "falhou" }
  rescue IOError
    nil
  end

  test "comeca fechado e deixa as chamadas passarem" do
    assert_equal :closed, @breaker.state
    assert_equal 42, @breaker.call { 42 }
  end

  test "abre depois de N falhas seguidas e falha rapido sem executar o bloco" do
    3.times { fail_once }
    assert_equal :open, @breaker.state

    executed = false
    assert_raises(CircuitBreaker::OpenError) { @breaker.call { executed = true } }
    assert_not executed, "com o disjuntor aberto a dependência não deve ser chamada"
  end

  test "sucesso no meio zera a contagem de falhas" do
    2.times { fail_once }
    @breaker.call { :ok }
    2.times { fail_once }
    assert_equal :closed, @breaker.state
  end

  test "depois do cooldown fica meio-aberto e um sucesso fecha" do
    3.times { fail_once }
    @now += 30
    assert_equal :half_open, @breaker.state
    assert_equal :ok, @breaker.call { :ok }
    assert_equal :closed, @breaker.state
    assert_equal [ %i[closed open], %i[open half_open], %i[half_open closed] ], @changes
  end

  test "falha na chamada de teste reabre o disjuntor" do
    3.times { fail_once }
    @now += 31
    fail_once
    assert_equal :open, @breaker.state

    @now += 10
    assert_raises(CircuitBreaker::OpenError) { @breaker.call { :ok } }
  end

  test "no estado meio-aberto so uma chamada de teste por vez" do
    3.times { fail_once }
    @now += 30
    concurrent = nil
    @breaker.call do
      concurrent = assert_raises(CircuitBreaker::OpenError) { @breaker.call { :outra } }
      :ok
    end
    assert_kind_of CircuitBreaker::OpenError, concurrent
    assert_equal :closed, @breaker.state
  end
end
