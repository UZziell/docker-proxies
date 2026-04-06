ARG IMAGE_REGISTRY
FROM ${IMAGE_REGISTRY}alpine:3.22

ARG SERVER_OR_CLIENT
ARG ARCHETECTURE=amd64
ARG RELEASE_TAG=latest

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=vaydns

WORKDIR /var/lib/vaydns

RUN addgroup -g ${GROUP_ID} ${USER_NAME} \
 && adduser -D -u ${USER_ID} -G ${USER_NAME} -H -s /sbin/nologin ${USER_NAME} \
 && mkdir -p /var/lib/vaydns && chown -R ${USER_ID}:${GROUP_ID} /var/lib/vaydns

RUN apk add --no-cache gcompat bash su-exec

ADD --chown=$USER_ID:$GROUP_ID --chmod=755 https://github.com/net2share/vaydns/releases/${RELEASE_TAG}/download/vaydns-${SERVER_OR_CLIENT}-linux-${ARCHETECTURE} /usr/local/bin/vaydns-${SERVER_OR_CLIENT}

EXPOSE 5300