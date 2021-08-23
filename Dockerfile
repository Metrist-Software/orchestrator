FROM canarymonitor/agent:build-base-2021.34 AS build

COPY mix.exs mix.lock install-runner.sh ./
#COPY config config
COPY priv priv
RUN ./install-runner.sh
RUN mix do deps.get, deps.compile
COPY lib lib
#COPY rel rel

RUN mix do compile, release

FROM canarymonitor/agent:runtime-base-2021.34 AS app

COPY --from=build --chown=nobody:nogroup /app/_build/prod/rel/bakeware/ ./
USER nobody:nogroup
# Bakeware's cache directory must exist in advance. Probably safer.
RUN mkdir .cache

CMD ["./orchestrator"]