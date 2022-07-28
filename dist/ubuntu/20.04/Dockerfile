FROM ubuntu:20.04 AS build

ENV REFRESHED_AT 20220728T160000Z
ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV MIX_ENV=prod

RUN apt-get update
RUN apt-get install -y build-essential zstd git curl unzip wget
RUN wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && dpkg -i erlang-solutions_2.0_all.deb
RUN apt-get update
RUN apt-get install -y esl-erlang elixir
RUN apt-get install -y ruby
RUN gem install fpm

WORKDIR /app

# We run under a UID with no HOME set so make sure that
# our tooling can write to where we need.
RUN mkdir /.mix && chmod 777 /.mix
RUN mkdir /.hex && chmod 777 /.hex
