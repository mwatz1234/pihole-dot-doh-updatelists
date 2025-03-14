ARG FRM='pihole/pihole:latest'
ARG TAG='latest'

FROM ${FRM}
ARG FRM
ARG TAG
ARG TARGETPLATFORM

RUN apk upgrade --no-cache
RUN apk add --no-cache sudo
RUN apk add --no-cache bash 
RUN apk add --no-cache nano 
RUN apk add --no-cache curl 
RUN apk add --no-cache wget 
RUN apk add --no-cache php-cli
RUN apk add --no-cache php-sqlite3
RUN apk add --no-cache php-intl
RUN apk add --no-cache php-curl
RUN apk add --no-cache stubby
#RUN apk upgrade --no-cache && \
#    apk add --no-cache sudo bash nano curl wget php-cli php-sqlite3 php-intl php-curl stubby

#RUN apt-get update && \
 #   apt-get install -Vy sudo bash nano curl wget php-cli php-sqlite3 php-intl php-curl stubby

ADD stuff /temp

RUN /bin/bash /temp/install.sh \
    && rm -f /temp/install.sh

RUN wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash /dev/stdin docker

RUN echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info
