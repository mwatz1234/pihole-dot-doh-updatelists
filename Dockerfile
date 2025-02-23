FROM pihole/pihole:latest

RUN apt-get update
RUN apt-get install -Vy sudo bash curl wget
RUN apt-get install -Vy php-cli php-sqlite3 
RUN apt-get install -Vy php-intl php-curl stubby

ADD stuff /temp

RUN /bin/bash /temp/install.sh \
    && rm -f /temp/install.sh

RUN wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash /dev/stdin docker

RUN echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info
