# Deployment doesn't work on Alpine
FROM php:7.0-cli AS deployer
ENV OSTICKET_VERSION=1.10.5
RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends git-core unzip
COPY mod-allow-agents-unassign-themselves-from-ticket.patch .
RUN set -x \
    && git clone -b v${OSTICKET_VERSION} --depth 1 https://github.com/osTicket/osTicket.git \
    && cd osTicket \
    # Patches
    && patch -p1 < ../mod-allow-agents-unassign-themselves-from-ticket.patch \
    # Deploy
    && php manage.php deploy -sv /install/data/upload \
    # Fix permissions for www-data
    && chmod 755 /install/data/upload \
    # Hide setup
    && mv /install/data/upload/setup /install/data/upload/setup_hidden \
    && chmod -R go= /install/data/upload/setup_hidden
RUN set -ex; \
    for lang in ar az bg ca cs da de el es_ES et fr hr hu it ja ko lt mk mn nl no fa pl pt_PT \
        pt_BR sk sl sr_CS fi sv_SE ro ru vi th tr uk zh_CN zh_TW; do \
        curl -so /install/data/upload/include/i18n/${lang}.phar \
            https://s3.amazonaws.com/downloads.osticket.com/lang/${lang}.phar; \
    done
RUN set -ex; \
    git clone --depth 1 https://github.com/devinsolutions/osTicket-plugins.git; \
    cd osTicket-plugins; \
    php make.php hydrate; \
    for plugin in $(find * -maxdepth 0 -type d ! -path doc ! -path lib); do \
        php -dphar.readonly=0 make.php build ${plugin}; \
        mv ${plugin}.phar /install/data/upload/include/plugins; \
    done
RUN set -ex; \
    git clone --depth 1 https://github.com/devinsolutions/osTicket-slack-plugin.git; \
    cd osTicket-slack-plugin; \
    mv slack /install/data/upload/include/plugins
COPY files /install

FROM php:7.0-fpm-alpine
RUN set -x \
    # Runtime dependencies
    && apk add --no-cache --update \
        ca-certificates \
        c-client \
        curl \
        icu \
        libintl \
        libpng \
        libxml2 \
        msmtp \
        nginx \
        openldap \
        openssl \
        supervisor \
    # Build dependencies
    && apk add --no-cache --virtual .build-deps \
        autoconf \
        curl-dev \
        g++ \
        gettext-dev \
        icu-dev \
        imap-dev \
        libpng-dev \
        libxml2-dev \
        make \
        openldap-dev \
        pcre-dev \
    # Install PHP extensions
    && docker-php-ext-configure imap --with-imap-ssl \
    && docker-php-ext-install \
        curl \
        gd \
        gettext \
        imap \
        intl \
        ldap \
        mbstring \
        mysqli \
        opcache \
        sockets \
        xml \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    # Create msmtp log
    && touch /var/log/msmtp.log \
    && chown www-data:www-data /var/log/msmtp.log \
    # File upload permissions
    && chown nginx:www-data /var/tmp/nginx \
    && chmod g+rx /var/tmp/nginx \
    # Clean up
    && apk del .build-deps \
    && rm -rf /var/cache/apk/*
COPY --from=deployer /install /
WORKDIR /data
CMD ["/data/bin/start.sh"]
EXPOSE 80
HEALTHCHECK CMD curl -fIsS http://localhost/ || exit 1
