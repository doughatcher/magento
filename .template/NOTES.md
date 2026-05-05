# Notes

## Architecture

All services share `network_mode: service:magento`, so everything is reachable on `127.0.0.1` from inside the magento container. This keeps the Magento config simple — every host is `127.0.0.1` regardless of compose service name.

```
┌──────────────────── magento container (network namespace owner) ─────────────────┐
│                                                                                  │
│  PHP-FPM / built-in server                                                       │
│                                                                                  │
│  ┌── db (MariaDB) ──┐ ┌── redis ──┐ ┌── ampq (RabbitMQ) ──┐ ┌── opensearch ──┐  │
│  │  127.0.0.1:3306  │ │ :6379     │ │     :5672            │ │  :9200          │  │
│  └──────────────────┘ └───────────┘ └──────────────────────┘ └─────────────────┘  │
│                                                                                  │
│  ┌── mailhog (SMTP catch-all) ──┐                                                │
│  │  smtp :1025  ui :8025        │                                                │
│  └──────────────────────────────┘                                                │
└──────────────────────────────────────────────────────────────────────────────────┘
        ▲
        │ (when nginx sidecar is enabled)
┌───────┴────────┐
│  nginx :80, :8443
│  proxies fastcgi to PHP-FPM via shared netns
└────────────────┘
```

## First-start flow (`commerce.sh`)

1. `set -o allexport && source .env` — pull workspace `.env` into the shell.
2. If `$COMPOSER_AUTH` is set and no `auth.json` exists, materialize one (works for Codespaces secrets / CI).
3. Configure git from `$VSCODE_GIT_NAME` / `$VSCODE_GIT_EMAIL`.
4. `wait_for_dependencies` — block until MariaDB, Redis, RabbitMQ, and OpenSearch accept connections.
5. If `app/etc/env.php` is missing:
   - If `composer.json` is missing too, `composer create-project --repository-url=https://repo.magento.com/ $COMMERCE_EDITION ./tmp` → move to root.
   - `composer install` → `bin/magento setup:install` → set sane defaults → disable Adobe IMS 2FA *before* TwoFactorAuth (the order matters — disabling them out of order leaves the IMS module enabled with no fallback).
   - Create admin: `admin / admin123` / `noreply@example.com`.
6. Run `$POST_INSTALL_CMD` if set (hook for sample data, fixtures, etc.).
7. Configure base URL based on mode:
   - Local builtin: `http://localhost:8080/`
   - Local fpm: `https://localhost:8443/`
   - Codespaces builtin: `http://$CODESPACE_NAME-8080.app.github.dev/` (port 8080)
   - Codespaces fpm: `https://$CODESPACE_NAME-80.app.github.dev/` (port 80)
8. `deploy:mode:set developer`, `indexer:reindex`, `cache:flush`.
9. Tail logs in background, start web server (`php-fpm` or `php -S 0.0.0.0:$PORT -t pub/`).

## Why `0.0.0.0` for built-in PHP server

GitHub Codespaces port-forwards via a TCP proxy that connects from the loopback interface inside the container, but only ports bound on `0.0.0.0` are reachable from the forwarded URL. Binding to `127.0.0.1` works locally but breaks Codespaces.

## `COMPOSER_AUTH` is a secret, not a variable

In CI workflows, `COMPOSER_AUTH` must be a repository **secret**, not a repository variable. It contains the literal contents of `auth.json` (a JSON object with `repo.magento.com` credentials). Variables are visible in workflow logs; secrets are masked.

## Codespaces vs. local

The template defaults to **PHP built-in** on port 8080 because it's a single process — no fastcgi handshake to debug, no SSL cert provisioning, and one less moving piece on first run. If you want production-like behavior (Nginx + FPM + HTTPS on 8443), set `PHP_MODE=fpm` in `.devcontainer/.env`.

## Maintenance

The template is published from this repository's working tree (`doughatcher/magento`), which is itself a live, exercised Magento installation. The `.template/build.sh` script copies the working tree to a scratch dir and substitutes `${templateOption:phpVersion}`, `${templateOption:composerVersion}`, and `${templateOption:commerceEdition}` into the appropriate files. To cut a release, bump `.template/devcontainer-template.json`'s `version`, commit, then push a tag matching `template-v<version>`.
