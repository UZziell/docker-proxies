ARG IMAGE_REGISTRY
FROM ${IMAGE_REGISTRY}alpine:3.22 AS downloader

ARG SERVER_OR_CLIENT
ARG ARCHETECTURE=AMD64

RUN apk add --no-cache tar && mkdir /tmp/masterdnsvpn
ADD https://github.com/masterking32/MasterDnsVPN/releases/latest/download/MasterDnsVPN_${SERVER_OR_CLIENT}_Linux_${ARCHETECTURE}.tar.gz /tmp/masterdnsvpn.tar.gz
RUN tar -xzf /tmp/masterdnsvpn.tar.gz -C /tmp/masterdnsvpn


FROM ${IMAGE_REGISTRY}alpine:3.22 AS final
ARG SERVER_OR_CLIENT
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=masterdnsvpn

WORKDIR /var/lib/masterdnsvpn

RUN addgroup -g ${GROUP_ID} ${USER_NAME} \
    && adduser -D -u ${USER_ID} -G ${USER_NAME} -H -s /sbin/nologin ${USER_NAME} \
    && mkdir -p /var/lib/masterdnsvpn && chown -R ${USER_ID}:${GROUP_ID} /var/lib/masterdnsvpn

COPY --from=downloader /tmp/masterdnsvpn/MasterDnsVPN_${SERVER_OR_CLIENT}* /usr/local/bin/masterdnsvpn-${SERVER_OR_CLIENT}
COPY --from=downloader /tmp/masterdnsvpn/*.toml /etc/masterdnsvpn/
COPY --from=downloader /tmp/masterdnsvpn/*.txt /var/lib/masterdnsvpn/

RUN export SERVER_OR_CLIENT_LOWER=$(echo "$SERVER_OR_CLIENT" | tr '[:upper:]' '[:lower:]') \
    && mv /usr/local/bin/masterdnsvpn-${SERVER_OR_CLIENT} /usr/local/bin/masterdnsvpn-${SERVER_OR_CLIENT_LOWER} \
    && chmod 755 /usr/local/bin/masterdnsvpn-${SERVER_OR_CLIENT_LOWER}
