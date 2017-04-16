FROM docker:17.04.0-dind

ENV RIOFS_GIT_COMMIT a01ec17bda2ec7363a15f072ecb7893972067ad0

# Extend dind with the aws sdk
RUN apk --no-cache update && \
    apk --no-cache add python py-pip py-setuptools ca-certificates groff less fuse alpine-sdk automake autoconf libxml2-dev glib-dev libevent-dev fuse-dev curl-dev bsd-compat-headers git bash supervisor && \
    pip --no-cache-dir install awscli && \
    rm -rf /var/cache/apk/*

RUN curl https://codeload.github.com/skoobe/riofs/zip/$RIOFS_GIT_COMMIT -o riofs.zip && \
    unzip -x riofs.zip && \
    rm riofs.zip && \
    cd riofs-$RIOFS_GIT_COMMIT && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    cd .. && \
    rm -rf riofs-$RIOFS_GIT_COMMIT

RUN mkdir /bids_dataset && mkdir /outputs && mkdir /var/log/docker

COPY run-bids-app.sh /run-bids-app.sh
COPY supervisord.conf /supervisord.conf

CMD supervisord -c /supervisord.conf
