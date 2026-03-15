#!/bin/bash

echo "Starting commerce.sh"

cd /var/www/html

if [ -f .env ]; then
    set -o allexport
    source .env
    set +o allexport
fi

if [ -n "$COMPOSER_AUTH" ] && [ ! -f auth.json ]; then
    echo "$COMPOSER_AUTH" > auth.json
    echo "Created auth.json from COMPOSER_AUTH environment variable"
fi

if [ ! -f ~/.gitconfig ] && [ -n "$VSCODE_GIT_NAME" ] && [ -n "$VSCODE_GIT_EMAIL" ]; then
    git config --global user.name "$VSCODE_GIT_NAME"
    git config --global user.email "$VSCODE_GIT_EMAIL"

    echo "Configured global git user.name as '$VSCODE_GIT_NAME' and user.email as '$VSCODE_GIT_EMAIL'"
fi

function wait_for_tcp_service() {
    local service_name=$1
    local host=$2
    local port=$3
    local retries=${4:-60}

    for ((attempt=1; attempt<=retries; attempt++)); do
        if (echo > /dev/tcp/$host/$port) >/dev/null 2>&1; then
            echo "$service_name is ready on $host:$port"
            return 0
        fi

        echo "Waiting for $service_name on $host:$port ($attempt/$retries)"
        sleep 2
    done

    echo "$service_name did not become ready on $host:$port" >&2
    return 1
}

function wait_for_http_service() {
    local service_name=$1
    local url=$2
    local retries=${3:-60}

    for ((attempt=1; attempt<=retries; attempt++)); do
        if curl -ksS --max-time 2 "$url" >/dev/null 2>&1; then
            echo "$service_name is ready at $url"
            return 0
        fi

        echo "Waiting for $service_name at $url ($attempt/$retries)"
        sleep 2
    done

    echo "$service_name did not become ready at $url" >&2
    return 1
}

function wait_for_dependencies() {
    wait_for_tcp_service "MariaDB" 127.0.0.1 3306
    wait_for_tcp_service "Redis" 127.0.0.1 6379
    wait_for_tcp_service "RabbitMQ" 127.0.0.1 5672
    wait_for_http_service "OpenSearch" "http://127.0.0.1:9200"
}

function configure_base_url() {
    local base_url=$1
    local use_secure=$2

    bin/magento config:set --lock-env web/unsecure/base_url "$base_url"
    bin/magento config:set --lock-env web/secure/base_url "$base_url"

    bin/magento config:set --lock-env web/secure/use_in_frontend "$use_secure"
    bin/magento config:set --lock-env web/secure/use_in_adminhtml "$use_secure"

    if [ -n "$CODESPACE_NAME" ]; then
        bin/magento config:set --lock-env web/url/redirect_to_base 0
    fi
}

set -e

: ${PHP_MODE:="builtin"}
: ${DEPLOY_MODE:="developer"}
: ${INSTALL_SAMPLE_DATA:="false"}
: ${COMMERCE_EDITION:="magento/project-community-edition"}
: ${SKIP_SETUP:="false"}

if [ "$PHP_MODE" == "builtin" ]; then
    : ${PORT:=8080}
    : ${USE_SECURE_URL:="0"}
    : ${PROTOCOL:="http"}
else
    : ${USE_SECURE_URL:="1"}
    : ${PORT:=8443}
    : ${PROTOCOL:="https"}
fi

: ${BASEURL:="$PROTOCOL://localhost:$PORT/"}

if [ -n "$CODESPACE_NAME" ]; then
    if [ "$PHP_MODE" == "fpm" ]; then
        PORT=80
        BASEURL="https://$CODESPACE_NAME-$PORT.app.github.dev/"
    else
        PORT=8080
        BASEURL="http://$CODESPACE_NAME-$PORT.app.github.dev/"
    fi
    USE_SECURE_URL="0"
    echo "Setting base URL to $BASEURL"
fi

if [ "$SKIP_SETUP" != "true" ]; then

    wait_for_dependencies

    if [ ! -f app/etc/env.php ]; then
        if [ -n "$MYSQL_DUMP_FILE" ]; then

            if [[ "$MYSQL_DUMP_FILE" == *.zip ]]; then
                unzip "$MYSQL_DUMP_FILE" -d /tmp
                MYSQL_DUMP_FILE=$(find /tmp -name '*.sql')
            fi

            echo "Importing MySQL dump file: $MYSQL_DUMP_FILE"
            mysql -h 127.0.0.1 -u magento -pmagento magento <"$MYSQL_DUMP_FILE"
        fi
    fi

    if [ ! -f composer.json ]; then

        composer create-project --repository-url=https://repo.magento.com/ $COMMERCE_EDITION ./tmp
        mv tmp/* .
    fi

    if [ -n "$COMPOSER_REQUIRES" ]; then
        composer require $COMPOSER_REQUIRES
    fi

    composer install

    if [ ! -f app/etc/env.php ]; then

        INSTALL="true"
        bin/magento setup:install \
            --backend-frontname=backend \
            --amqp-host=127.0.0.1 \
            --amqp-port=5672 \
            --amqp-user=guest \
            --amqp-password=guest \
            --db-host=127.0.0.1 \
            --db-user=magento \
            --db-password=magento \
            --db-name=magento \
            --search-engine=opensearch \
            --opensearch-host=127.0.0.1 \
            --opensearch-port=9200 \
            --opensearch-index-prefix=magento2 \
            --opensearch-enable-auth=1 \
            --opensearch-username=admin \
            --opensearch-password=fhgLpkH66PwD \
            --opensearch-timeout=15 \
            --session-save=redis \
            --session-save-redis-host=127.0.0.1 \
            --session-save-redis-port=6379 \
            --session-save-redis-db=2 \
            --session-save-redis-max-concurrency=20 \
            --cache-backend=redis \
            --cache-backend-redis-server=127.0.0.1 \
            --cache-backend-redis-db=0 \
            --cache-backend-redis-port=6379 \
            --page-cache=redis \
            --page-cache-redis-server=127.0.0.1 \
            --page-cache-redis-db=1 \
            --page-cache-redis-port=6379

        bin/magento config:set --lock-env web/seo/use_rewrites 1
        bin/magento config:set --lock-env system/full_page_cache/caching_application 1
        bin/magento config:set --lock-env system/full_page_cache/ttl 604800
        bin/magento config:set --lock-env catalog/search/enable_eav_indexer 1
        bin/magento config:set --lock-env dev/static/sign 0

        bin/magento module:disable Magento_AdminAdobeImsTwoFactorAuth Magento_TwoFactorAuth

        bin/magento cache:enable block_html full_page

        bin/magento admin:user:create --admin-user admin --admin-password admin123 --admin-firstname demo --admin-lastname user --admin-email noreply@example.com

        if [ -n "$POST_INSTALL_CMD" ]; then
            eval "$POST_INSTALL_CMD"
        fi

        configure_base_url $BASEURL $USE_SECURE_URL

        if [ -n "$CODESPACE_NAME" ]; then
            bin/magento config:set --lock-env web/url/redirect_to_base 0
            # Remove protocol and trailing slash from BASEURL for cookie domain
            cookie_domain=".${BASEURL#https://}"
            cookie_domain="${cookie_domain%/}"
            php bin/magento config:set web/cookie/cookie_domain "$cookie_domain"
        fi

        bin/magento deploy:mode:set $DEPLOY_MODE
        bin/magento indexer:reindex
    else
        configure_base_url $BASEURL $USE_SECURE_URL
        bin/magento setup:upgrade
    fi

    bin/magento cache:flush

fi

# run the server

if [ "$TEST_MODE" == "true" ]; then
    echo "devcontainer built successfully and started commerce.sh and ran installation. Skipping server start."
    exit 0
fi

tail -f var/log/* &

if [ "$PHP_MODE" == "fpm" ]; then
    echo "Running in FPM mode"
    php-fpm --allow-to-run-as-root --nodaemonize
elif [ "$PHP_MODE" == "builtin" ]; then
    echo "Running in built-in server mode on 0.0.0.0:$PORT"
    php -S 0.0.0.0:$PORT -t ./pub/ ./phpserver/router.php
fi
