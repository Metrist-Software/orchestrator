FROM centos:7 AS build

ENV REFRESHED_AT 20220926T210646Z
ENV LANG=C.UTF-8
ENV MIX_ENV=prod

RUN yum -y update
RUN yum -y groupinstall 'Development Tools'
RUN yum -y install openssl-devel ncurses-devel libcurl-devel

RUN git config --global advice.detachedHead false; \
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.10.2
RUN echo '. $HOME/.asdf/asdf.sh' >> $HOME/.bashrc
SHELL ["/bin/bash", "--login", "-c"]
RUN asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git && \
    asdf plugin add ruby   https://github.com/asdf-vm/asdf-ruby.git && \
    asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
RUN asdf install erlang 24.3.4 
RUN asdf install ruby   3.1.2
RUN asdf install elixir 1.13.4-otp-24

WORKDIR /app

# We run under a UID with no HOME set so make sure that
# our tooling can write to where we need.
RUN mkdir /.mix && chmod 777 /.mix
RUN mkdir /.hex && chmod 777 /.hex

ENTRYPOINT ["/bin/bash"]
