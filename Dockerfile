FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      build-essential \
      ca-certificates \
      cpanminus \
      irssi \
      libio-socket-ssl-perl \
      libnet-ssleay-perl \
      libssl-dev \
      libxml2-dev \
      zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY cpanfile ./
RUN perl -MHTTP::Tiny -e 'my ($ok, $why) = HTTP::Tiny->can_ssl; die "$why\n" unless $ok; print "HTTPS support OK\n"' \
 && cpanm --mirror https://cpan.metacpan.org --mirror-only --notest --installdeps .

COPY . .

CMD ["make", "check"]
