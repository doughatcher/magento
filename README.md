# Magento Community Edition

Open-source Magento 2 Community Edition development environment using devcontainers.

## What's Included

- **Devcontainer**: Full Magento development environment with PHP 8.3, MariaDB, Redis, RabbitMQ, OpenSearch, Mailhog, and Nginx
- **Pre-built Docker images**: Published to `ghcr.io/doughatcher/magento` for fast container startup
- **Task runner**: `justfile` with common Magento operations (shell, up, down, rebuild, cache flush, reindex, etc.)
- **CI/CD**: GitHub Actions for code quality (DI compile, static content deploy, PHPCS, PHPMD, composer validate)
- **E2E tests**: Playwright-based checkout flow and admin login tests
- **Luma sample data**: Bundled for immediate storefront testing

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) or [Podman](https://podman.io/)
- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- Magento Marketplace credentials ([get them here](https://commercemarketplace.adobe.com/customer/accessKeys/))

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/doughatcher/magento.git
   cd magento
   ```

2. Create `auth.json` with your Magento Marketplace credentials:
   ```json
   {
     "http-basic": {
       "repo.magento.com": {
         "username": "<your-public-key>",
         "password": "<your-private-key>"
       }
     }
   }
   ```

3. Open in VS Code and reopen in container (or use the CLI):
   ```bash
   just up
   ```

4. The first startup runs `composer install` and `bin/magento setup:install` automatically.

### Using the Justfile

```bash
just shell          # Get a shell inside the devcontainer
just up             # Start the devcontainer
just down           # Stop (preserves volumes)
just rebuild        # Rebuild from scratch
just magento <cmd>  # Run bin/magento commands
just composer <cmd> # Run composer commands
just flush          # Flush all caches
just reindex        # Reindex all indexers
just status         # Show container status
just logs           # Tail Magento logs
just tunnel         # Expose via Cloudflare quick tunnel
just test-e2e       # Run all E2E tests
just test-checkout  # Run checkout flow test
just test-admin     # Run admin login test
just test-report    # View Playwright HTML report
```

### Accessing Magento

| Service      | URL                         |
|--------------|-----------------------------|
| Storefront   | https://localhost:8443      |
| Admin Panel  | https://localhost:8443/backend |
| Mailhog      | http://localhost:8025       |

Default admin credentials are set in `.devcontainer/commerce.sh` (check `ADMIN_USER` / `ADMIN_PASSWORD`).

## Architecture

All services share a single network namespace (`network_mode: service:magento`), so everything is accessible on `127.0.0.1` inside the container:

- **magento** — PHP 8.3 FPM + CLI (port 8443 via Nginx, or PHP built-in server)
- **db** — MariaDB 10.6 (port 3306)
- **redis** — Redis 7.4 (port 6379)
- **rabbitmq** — RabbitMQ 3.13 (port 5672)
- **opensearch** — OpenSearch 2.19 (port 9200)
- **mailhog** — MailHog (SMTP 1025, UI 8025)
- **nginx** — Nginx reverse proxy (ports 8080, 8443)

## CI/CD

### Code Quality (ci.yml)

Runs on every push and PR:
- Composer install + workspace caching
- DI compilation (`setup:di:compile`)
- Static content deployment
- PHPCS (Magento coding standards)
- PHPMD
- Composer validation

### Docker Image Builds (docker-build-push.yml)

Builds and pushes multi-arch (amd64/arm64) images to GHCR on pushes to `main` when Dockerfile or conf files change.

### E2E Tests (e2e.yml)

Manual workflow dispatch — runs Playwright checkout and admin login tests against any URL.

## Repository Secrets

Set these in GitHub repository settings:

| Secret/Variable   | Description                           |
|-------------------|---------------------------------------|
| `COMPOSER_AUTH`   | (Secret) Magento Marketplace auth JSON |
| `MAGENTO_ADMIN_URI` | Admin URL path (e.g., `/backend`)   |
| `MAGENTO_ADMIN_USER` | Admin username for E2E tests       |
| `MAGENTO_ADMIN_PASS` | Admin password for E2E tests       |

## License

OSL-3.0
