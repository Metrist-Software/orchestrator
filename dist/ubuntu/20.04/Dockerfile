FROM ubuntu:20.04 AS build

ENV REFRESHED_AT 20230214T165749Z
ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV MIX_ENV=prod

ENV ERLANG_VERSION 25.2.2
ENV ELIXIR_VERSION 1.14.3

RUN apt-get update
RUN apt-get install -y build-essential zstd git curl unzip wget libcurl4-openssl-dev libncurses-dev libssl-dev

RUN cd /tmp && \
  wget "https://github.com/erlang/otp/releases/download/OTP-$ERLANG_VERSION/otp_src_$ERLANG_VERSION.tar.gz" -O otp.tar.gz && \
  mkdir otp && \
  tar -xzf otp.tar.gz -C otp --strip-components=1 && \
  cd otp && \
  ./configure && make && make install && rm -rf /tmp/otp*

RUN cd /tmp && \
  wget "https://github.com/elixir-lang/elixir/archive/v$ELIXIR_VERSION.tar.gz" -O elixir.tar.gz && \
  mkdir elixir && \
  tar -xzf elixir.tar.gz -C elixir --strip-components=1 && \
  cd elixir && \
  make && make install && rm -rf /tmp/elixir*

RUN apt-get update
RUN apt-get install -y ruby
RUN gem install fpm

WORKDIR /app

# We run under a UID with no HOME set so make sure that
# our tooling can write to where we need.
RUN mkdir /.mix && chmod 777 /.mix
RUN mkdir /.hex && chmod 777 /.hex
RUN mkdir /.cache && chmod 777 /.cache
