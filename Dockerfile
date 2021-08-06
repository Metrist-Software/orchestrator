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

#RUN apk add --no-cache openssl ncurses-libs libgc++ gcompat
RUN apt-get update && \
    apt-get install -y openssl ca-certificates curl

# The Zoom client monitor needs Chromium/Chrome. Bundling doesn't work due to DLL dependencies in the
# downloaded version, so we install Google's Debian package here. We still use the actual Chromium that
# puppeteer bundles, but this will ensure we have all the prerequisites.
RUN cd /tmp; curl -O https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; apt install -y ./*.deb && \
    rm -rf /var/cache/apt /var/lib/apt/lists

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
