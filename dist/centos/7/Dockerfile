FROM centos:7 AS build

ENV REFRESHED_AT 20220926T210646Z
ENV LANG=C.UTF-8
ENV MIX_ENV=prod

RUN yum -y update
RUN yum -y groupinstall 'Development Tools'
RUN yum -y install libcurl-devel wget

RUN wget https://packages.erlang-solutions.com/erlang-solutions-2.0-1.noarch.rpm
RUN rpm -Uvh erlang-solutions-2.0-1.noarch.rpm
RUN yum -y install esl-erlang elixir ruby
RUN gem install fpm

WORKDIR /app

# We run under a UID with no HOME set so make sure that
# our tooling can write to where we need.
RUN mkdir /.mix && chmod 777 /.mix
RUN mkdir /.hex && chmod 777 /.hex
