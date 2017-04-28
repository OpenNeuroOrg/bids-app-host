FROM docker:17.04.0-dind

ENV S3FS_VERSION master

# Extend dind with the aws sdk
RUN apk --no-cache update && \
    apk add --no-cache --update \
    python \
    ca-certificates \
    groff \
    less \
    fuse \
    alpine-sdk \
    automake \
    autoconf \
    libxml2-dev \
    glib-dev \
    libevent-dev \
    fuse-dev \
    curl-dev \
    bsd-compat-headers \
    bash

RUN mkdir /usr/src && \
    curl -L https://github.com/s3fs-fuse/s3fs-fuse/archive/${S3FS_VERSION}.tar.gz | tar zxv -C /usr/src && \
    cd /usr/src/s3fs-fuse-${S3FS_VERSION} && \
    ./autogen.sh && \
    ./configure --prefix=/usr && \
    make && \
    make install && \
    rm -r /usr/src

RUN mkdir /bids_dataset && mkdir /outputs && mkdir /var/log/docker

COPY run-bids-app.sh /usr/local/bin/run-bids-app.sh
COPY dockerd.sh /usr/local/bin/dockerd.sh

CMD /usr/local/bin/run-bids-app.sh
