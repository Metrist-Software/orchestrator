FROM elixir:1.11-alpine AS build

ENV REFRESHED_AT 20210428T213742Z
RUN apk add --no-cache build-base zstd git curl unzip

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock install-runner.sh ./
#COPY config config
COPY priv priv
RUN ./install-runner.sh
RUN mix do deps.get, deps.compile
COPY lib lib
#COPY rel rel

RUN mix do compile, release

# This is valid as long as the elixir image above is based on an erlang image that
# is built from Alpine 3.13.
FROM alpine:3.13 AS app

RUN apk add --no-cache openssl ncurses-libs libgc++ gcompat

WORKDIR /app
ENV HOME=/app

# Make .NET happy.
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1


RUN chown nobody:nobody /app
COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/bakeware/ ./
USER nobody:nobody
# Bakeware's cache directory must exist in advance. Probably safer.
RUN mkdir .cache

CMD ["./orchestrator"]
