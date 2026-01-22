ARG IMAGE_REGISTRY
FROM ${IMAGE_REGISTRY}alpine:3.22

ARG SERVER_OR_CLIENT
ARG ARCHETECTURE=amd64

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=dnstt

WORKDIR /var/lib/dnstt

RUN addgroup -g ${GROUP_ID} ${USER_NAME} \
 && adduser -D -u ${USER_ID} -G ${USER_NAME} -H -s /sbin/nologin ${USER_NAME} \
 && mkdir -p /var/lib/dnstt && chown -R ${USER_ID}:${GROUP_ID} /var/lib/dnstt

RUN apk add --no-cache bash su-exec

ADD --chown=$USER_ID:$GROUP_ID --chmod=755 https://dnstt.network/dnstt-${SERVER_OR_CLIENT}-linux-${ARCHETECTURE} /usr/local/bin/dnstt-${SERVER_OR_CLIENT}
RUN chmod 755 /usr/local/bin/dnstt-${SERVER_OR_CLIENT}

EXPOSE 5300