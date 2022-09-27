FROM ubuntu:22.04 AS build

ENV REFRESHED_AT 20220926T210646Z
ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV MIX_ENV=prod

# Jammy is not setup as a distribution by Erlang Solutions, so grab the packages manually.
RUN apt-get update
RUN apt-get install -y build-essential zstd git curl unzip wget libcurl4-openssl-dev
RUN wget https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc; apt-key add erlang_solutions.asc
RUN wget https://packages.erlang-solutions.com/erlang/debian/pool/esl-erlang_25.0.3-1~ubuntu~jammy_amd64.deb
RUN wget https://packages.erlang-solutions.com/erlang/debian/pool/elixir_1.13.4-1~ubuntu~focal_all.deb
RUN apt-get install -y ruby ./*.deb
RUN gem install fpm

WORKDIR /app

# We run under a UID with no HOME set so make sure that
# our tooling can write to where we need.
RUN mkdir /.mix && chmod 777 /.mix
RUN mkdir /.hex && chmod 777 /.hex
