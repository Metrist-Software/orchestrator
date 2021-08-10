FROM elixir:1.11-slim AS build

ENV REFRESHED_AT 20210712T152504Z
RUN apt-get update
RUN apt-get install -y build-essential zstd git curl unzip

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV LANG=C.UTF-8
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
# is built from this image.
FROM debian:buster AS app

# nss3, nspr4, libexpat1, fonts-freefont-ttf needed for the Zoom client's bundled Chromium
RUN apt-get update && \
    apt-get install -y openssl ca-certificates curl libnss3 libnspr4 libexpat1 fonts-freefont-ttf && \
    rm -rf /var/cache/apt /var/lib/apt


WORKDIR /app
ENV HOME=/app
ENV LANG=C.UTF-8

# Make .NET happy.
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

RUN chown nobody:nogroup /app
COPY --from=build --chown=nobody:nogroup /app/_build/prod/rel/bakeware/ ./
USER nobody:nogroup
# Bakeware's cache directory must exist in advance. Probably safer.
RUN mkdir .cache

CMD ["./orchestrator"]
