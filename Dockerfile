FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      build-essential \
      ca-certificates \
      cpanminus \
      irssi \
      libssl-dev \
      libxml2-dev \
      zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY cpanfile ./
RUN cpanm --notest --installdeps .

COPY . .

CMD ["make", "check"]
