ARG IMAGE_REGISTRY
FROM ${IMAGE_REGISTRY}debian:stable-20260610-slim

ENV DEBIAN_FRONTEND=noninteractive
ARG ARCHETECTURE=amd64
ARG NIPOVPN_VERSION

ADD https://github.com/MortezaBashsiz/nipovpn/releases/download/v${NIPOVPN_VERSION}/nipovpn_${NIPOVPN_VERSION}_${ARCHETECTURE}.deb /tmp/nipovpn.deb

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libyaml-cpp0.8 && \
    rm -rf /var/lib/apt/lists/* && \
    dpkg -i /tmp/nipovpn.deb && \
    rm /tmp/nipovpn.deb  && \
    ln -sf /dev/stdout /var/log/nipovpn/nipovpn.log

# ARG USER_ID=1000
# ARG GROUP_ID=1000
# ARG USER_NAME=nipovpn
# RUN groupadd --gid ${GROUP_ID} ${USER_NAME} \
#     && useradd --uid ${USER_ID} --gid ${GROUP_ID} --no-create-home --shell /usr/sbin/nologin ${USER_NAME} \
#     && install -d -o ${USER_ID} -g ${GROUP_ID} /var/lib/nipovpn
# USER 1000