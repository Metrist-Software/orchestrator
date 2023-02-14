FROM public.ecr.aws/metrist/orchestrator:build-base-2023.07 AS build

COPY mix.exs mix.lock install-runner.sh ./
COPY config config
COPY priv priv
ARG GITHUB_REF=""
RUN ./install-runner.sh $GITHUB_REF
RUN mix do deps.get, deps.compile
COPY lib lib
COPY rel rel

RUN mix do compile, release

FROM public.ecr.aws/metrist/orchestrator:runtime-base-2023.07 AS app

COPY --from=build --chown=nobody:nogroup /app/_build/prod/rel/bakeware/ ./
USER nobody:nogroup
# Erlexec wants this.
ENV USER=nobody
# Bakeware's cache directory must exist in advance. Probably safer.
RUN mkdir .cache

CMD ["./orchestrator"]
