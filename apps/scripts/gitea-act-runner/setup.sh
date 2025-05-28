#!/bin/sh
set -e

apk add --no-cache \
  alpine-sdk \
  build-base \
  curl \
  file \
  git \
  gzip \
  libc6-compat \
  libx11-dev \
  musl-dev \
  ncurses \
  nodejs
