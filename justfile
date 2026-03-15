# Magento Community Edition — devcontainer task runner

# Bazzite /var/home fix: devcontainer labels store the path used at creation
# time (/home/me/...) but justfile_directory() resolves symlinks (/var/home/...).
project := replace(justfile_directory(), "/var/home/", "/home/")

# Container name for docker exec
container := "magento_devcontainer-magento-1"

# Get a shell inside the devcontainer
shell:
    devcontainer exec --workspace-folder {{project}} bash

# Start the devcontainer
up:
    devcontainer up --workspace-folder {{project}}

# Stop the devcontainer (preserves volumes)
down:
    devcontainer down --workspace-folder {{project}}

# Rebuild the devcontainer from scratch
rebuild:
    devcontainer up --workspace-folder {{project}} --remove-existing-container

# Run a Magento CLI command (e.g., just magento cache:flush)
magento *args:
    docker exec {{container}} bash -c "cd /var/www/html && bin/magento {{args}}"

# Run composer inside the container
composer *args:
    docker exec {{container}} bash -c "cd /var/www/html && composer {{args}}"

# Flush all Magento caches
flush:
    docker exec {{container}} bash -c "cd /var/www/html && bin/magento cache:flush"

# Reindex all Magento indexers
reindex:
    docker exec {{container}} bash -c "cd /var/www/html && bin/magento indexer:reindex"

# Show container status
status:
    @docker ps --filter "name=magento_devcontainer"

# Tail Magento logs
logs:
    docker exec {{container}} tail -f /var/www/html/var/log/system.log /var/www/html/var/log/exception.log

# Expose HTTPS port for remote access (iPad, phone) — prints URL then stays running
# Sets Magento base URL to the tunnel hostname so CSS/JS/redirects work.
# Restores localhost base URL on exit (Ctrl+C).
tunnel port="8443":
    #!/usr/bin/env bash
    CONTAINER="{{container}}"
    ORIGINAL_BASE="https://localhost:{{port}}/"

    restore_base_url() {
        echo ""
        echo "  Restoring base URL to $ORIGINAL_BASE..."
        docker exec "$CONTAINER" bash -c "cd /var/www/html && \
            bin/magento config:set --lock-env web/unsecure/base_url '$ORIGINAL_BASE' && \
            bin/magento config:set --lock-env web/secure/base_url '$ORIGINAL_BASE' && \
            bin/magento config:set --lock-env web/url/redirect_to_base 1 && \
            bin/magento cache:flush" 2>/dev/null
        echo "  Base URL restored."
    }

    LOG=$(mktemp)
    cleanup() {
        restore_base_url
        kill "$PID" 2>/dev/null
        rm -f "$LOG"
    }
    trap cleanup EXIT

    cloudflared tunnel --no-autoupdate --url https://localhost:{{port}} \
        --config /dev/null --credentials-file /dev/null --metrics localhost:0 \
        --no-tls-verify 2>"$LOG" &
    PID=$!

    URL=""
    for i in $(seq 1 30); do
        URL=$(grep -oP 'https://[a-z]+-[a-z]+-[a-z]+-[a-z]+\.trycloudflare\.com' "$LOG" 2>/dev/null || true)
        if [ -n "$URL" ]; then break; fi
        sleep 1
    done
    if [ -z "$URL" ]; then
        echo "Failed to start tunnel:"
        cat "$LOG"
        exit 1
    fi

    # Set Magento base URL to tunnel hostname
    echo "  Setting base URL to $URL/..."
    docker exec "$CONTAINER" bash -c "cd /var/www/html && \
        bin/magento config:set --lock-env web/unsecure/base_url '$URL/' && \
        bin/magento config:set --lock-env web/secure/base_url '$URL/' && \
        bin/magento config:set --lock-env web/url/redirect_to_base 0 && \
        bin/magento cache:flush" 2>/dev/null

    echo ""
    echo "  Tunnel is live:"
    echo "  $URL"
    echo ""
    echo "  Press Ctrl+C to stop (base URL will be restored to localhost)"
    echo ""
    wait $PID

# Run all E2E tests
test-e2e *args:
    npx playwright test --config tests/e2e/playwright.config.ts {{args}}

# Run checkout flow test
test-checkout:
    npx playwright test --config tests/e2e/playwright.config.ts checkout

# Run admin login test
test-admin:
    npx playwright test --config tests/e2e/playwright.config.ts admin-login

# View the last Playwright HTML test report
test-report:
    npx playwright show-report tests/e2e/playwright-report
