# syntax=docker/dockerfile:1.7
#
# Frontend de PRODUÇÃO: build estático servido por Nginx sem privilégios.
# (Antes: servidor de desenvolvimento do Vite exposto com --host, rodando
# como root e com dependências vulneráveis do próprio dev server.)

# ---------- build ----------
FROM docker.io/library/node:24.22.1-alpine3.24 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
# A API é servida na MESMA origem, em /api, pelo balanceador.
ARG VITE_API_URL=/api
ENV VITE_API_URL=${VITE_API_URL}
RUN npm run build

# ---------- runtime ----------
FROM docker.io/nginxinc/nginx-unprivileged:1.31.7-alpine3.24

# A tag da imagem fica congelada, mas os pacotes do Alpine continuam recebendo
# correção. Sem este upgrade, um CVE HIGH/CRITICAL com fix publicado depois do
# build da tag reprova o gate do Trivy no CD.
# A imagem já vem como uid 101; pacotes só instalam como root.
USER root
RUN apk upgrade --no-cache && apk add --no-cache curl

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY nginx/security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY --from=build --chown=101:101 /app/dist /usr/share/nginx/html

# curl vem da imagem (wget não). Escuta na 8080, sem privilégio de root.
USER 101
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD ["curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1:8080/healthz"]
