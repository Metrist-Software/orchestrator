FROM registry.access.redhat.com/ubi7/ruby-27 AS build

USER root

ENV REFRESHED_AT 20230111T153816Z
# Using en_US.UTF-8 since C.UTF-8 not available in rhel
ENV LANG=en_US.UTF-8
ENV MIX_ENV=prod

ENV ERLANG_VERSION 25.1.1
ENV ELIXIR_VERSION 1.14.1

RUN yum install -y --disableplugin=subscription-manager git gcc openssl-devel ncurses-devel wget rpmdevtools rpmlint && \
    yum clean -y all && rm -rf /var/cache/yum

COPY bin/rpmdevtools-8.3-7.el7.noarch.rpm /tmp

USER default

RUN gem install fpm

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

WORKDIR /app

# We run under a UID with no HOME set so make sure that
# our tooling can write to where we need.
RUN mkdir /.mix && chmod 777 /.mix
RUN mkdir /.hex && chmod 777 /.hex
RUN mkdir /.cache && chmod 777 /.cache

