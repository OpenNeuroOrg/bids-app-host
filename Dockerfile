FROM docker:17.04.0-dind

ENV S3FS_VERSION master

# Extend dind with the aws sdk
RUN apk --no-cache update && \
    apk --no-cache add python py-pip py-setuptools ca-certificates groff less fuse alpine-sdk automake autoconf libxml2-dev glib-dev libevent-dev fuse-dev curl-dev bsd-compat-headers git bash supervisor && \
    pip --no-cache-dir install awscli && \
    rm -rf /var/cache/apk/*

RUN mkdir /usr/src && \
    curl -L https://github.com/s3fs-fuse/s3fs-fuse/archive/${S3FS_VERSION}.tar.gz | tar zxv -C /usr/src && \
    cd /usr/src/s3fs-fuse-${S3FS_VERSION} && \
    ./autogen.sh && \
    ./configure --prefix=/usr && \
    make && \
    make install && \
    rm -r /usr/src

RUN mkdir /bids_dataset && mkdir /outputs && mkdir /var/log/docker

COPY run-bids-app.sh /run-bids-app.sh
COPY supervisord.conf /supervisord.conf

CMD supervisord -c /supervisord.conf
