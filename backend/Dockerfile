# syntax=docker/dockerfile:1.7
#
# Imagem de PRODUÇÃO da API (antes: modo development, root, ferramentas de
# compilação na imagem final e código montado por volume).
#
#   docker build -t coursesphere-api ./backend
#
ARG RUBY_VERSION=4.0.9

# ---------- base: só o necessário para RODAR ----------
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libpq5 libjemalloc2 libyaml-0-2 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so \
    BOOTSNAP_READONLY=true \
    BOOTSNAP_CACHE_DIR=/rails/.bootsnap \
    RAILS_LOG_LEVEL=info \
    WEB_CONCURRENCY=1 \
    RAILS_MAX_THREADS=5 \
    LANG=C.UTF-8

# ---------- build: compila as gems nativas ----------
FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    BOOTSNAP_READONLY= bundle exec bootsnap precompile --gemfile

COPY . .
RUN BOOTSNAP_READONLY= bundle exec bootsnap precompile app/ lib/ && \
    chmod +x entrypoint.sh && \
    mkdir -p tmp/pids log

# ---------- final ----------
FROM base

# Usuário sem privilégios (uid 1000). Nada roda como root.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --chown=rails:rails /rails /rails

USER 1000:1000

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

EXPOSE 3000

# O orquestrador (compose/k8s) usa /health/live e /health/ready; este
# HEALTHCHECK cobre "docker run" isolado.
HEALTHCHECK --interval=15s --timeout=3s --start-period=30s --retries=3 \
  CMD ["ruby", "-rnet/http", "-e", "exit(Net::HTTP.get_response(URI('http://127.0.0.1:3000/health/live')).is_a?(Net::HTTPSuccess) ? 0 : 1)"]

ENTRYPOINT ["/rails/entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
