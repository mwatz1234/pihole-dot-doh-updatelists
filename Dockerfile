#---------------------------------------
# Base image
#---------------------------------------
ARG FRM='pihole/pihole:latest'
ARG TAG='latest'
ARG TARGETPLATFORM
FROM ${FRM}

# Re-declare TARGETPLATFORM for use in RUN commands (BuildKit requirement)
ARG TARGETPLATFORM

USER root

#---------------------------------------
# Install dependencies
#---------------------------------------
RUN apk add --no-cache \
        bash \
        curl \
        wget \
        git \
        sudo \
        nano \
        php \
        php-curl \
        php-intl \
        php-openssl \
        php-pcntl \
        php-posix \
        php-pdo_sqlite

#---------------------------------------
# Install dnsproxy + pihole-updatelists
#---------------------------------------
COPY stuff /temp
RUN chmod +x /temp/install.sh \
    && TARGETPLATFORM=${TARGETPLATFORM} /bin/bash /temp/install.sh \
    && wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash -s docker \
    && rm -rf /temp

#---------------------------------------
# Record build info
#---------------------------------------
RUN echo "$(date "+%d.%m.%Y %T") Built from ${FRM} with tag ${TAG}" >> /build_date.info

#---------------------------------------
# Use Pi-hole's default entrypoint
#---------------------------------------
