FROM canarymonitor/agent:build-base-2022.19 AS build

COPY mix.exs mix.lock install-runner.sh ./
COPY config config
COPY priv priv
ARG GITHUB_REF=""
RUN ./install-runner.sh $GITHUB_REF
RUN mix do deps.get, deps.compile
COPY lib lib
#COPY rel rel

RUN mix do compile, release

FROM canarymonitor/agent:runtime-base-2022.19 AS app

COPY --from=build --chown=nobody:nogroup /app/_build/prod/rel/bakeware/ ./
USER nobody:nogroup
# Bakeware's cache directory must exist in advance. Probably safer.
RUN mkdir .cache

CMD ["./orchestrator"]
