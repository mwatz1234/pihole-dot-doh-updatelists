ARG FRM='pihole/pihole:latest'
ARG TAG='latest'

FROM ${FRM}
ARG FRM
ARG TAG
ARG TARGETPLATFORM

ADD stuff /temp

RUN apt-get update && \
    apt-get install -Vy sudo bash nano curl wget php-cli php-sqlite3 php-intl php-curl stubby && \
    /bin/bash /temp/install.sh && \
    rm -f /temp/install.sh && \
    wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash /dev/stdin docker && \
    echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info
