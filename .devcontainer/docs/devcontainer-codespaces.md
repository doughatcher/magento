# Devcontainer & Codespaces Setup

## Overview

This devcontainer runs Magento with multiple service components via Docker Compose:

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub Codespaces / Local Dev Container                   │
│                                                             │
│  ┌─────────────────────┐    ┌──────────────────────────┐  │
│  │   magento service   │    │    nginx sidecar         │  │
│  │   (PHP/FPM)         │◄──►│    (port 80, 8443)      │  │
│  │   port 9000         │    │                          │  │
│  └─────────────────────┘    └──────────────────────────┘  │
│           │                                                    │
│  ┌────────┴────────┬────────────┬──────────┬────────────┐  │
│  │  db (MariaDB)   │  redis     │  rabbitmq│  opensearch│  │
│  │  port 3306      │  port 6379 │  port5672│  port 9200 │  │
│  └─────────────────┴────────────┴──────────┴────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Port Mapping

| Port | Service | Notes |
|------|---------|-------|
| 80   | HTTP    | nginx → PHP-FPM via fastcgi |
| 8443 | HTTPS   | nginx with self-signed cert |
| 9000 | Xdebug  | PHP-FPM pool |
| 9003 | Xdebug  | VS Code debug port |
| 8025 | Mailhog | Email testing UI |
| 1025 | Mailhog | SMTP catch-all |

## Access URLs

- **Local**: http://localhost:8080 (PHP built-in) or https://localhost:8443 (nginx)
- **Codespaces**: https://{codespace}-{port}.app.github.dev/

## How It Works

### Docker Compose Files

1. **docker-compose.yaml** - Base services
   - `magento` - Main PHP container
   - `db` - MariaDB
   - `redis` - Cache/sessions
   - `amqp` - RabbitMQ  
   - `opensearch` - Search
   - `mailhog` - Email testing

2. **docker-compose-nginx.yaml** - nginx sidecar overlay
   - Adds `nginx` service that shares network with magento
   - Sets `PHP_MODE: fpm` environment variable

### devcontainer.json

Uses **both** compose files to enable nginx sidecar:
```json
"dockerComposeFile": [
  "docker-compose.yaml",
  "docker-compose-nginx.yaml"
]
```

### commerce.sh Flow

1. Runs after container creation
2. Installs Magento if not present
3. Starts the appropriate web server based on `PHP_MODE`:
   - `fpm` → runs `php-fpm` (works with nginx sidecar)
   - `builtin` → runs `php -S` (PHP's built-in dev server)

### Environment Variables

| Variable | Default | Codespaces | Description |
|----------|---------|------------|-------------|
| `PHP_MODE` | `builtin` | `fpm` | Web server mode |
| `PORT` | 8080 | 80 | HTTP port |
| `USE_SECURE_URL` | 0 | 0 | HTTPS enforcement |
| `BASEURL` | http://localhost:8080/ | https://{codespace}-{port}.app.github.dev/ | Store URL |

## Common Issues

### Port 80 Already in Use

**Symptom**: Error starting nginx/PHP server, "Address already in use"

**Cause**: Both nginx sidecar and commerce.sh trying to use port 80

**Resolution**:
- Ensure `PHP_MODE=fpm` is set (via docker-compose or .env)
- commerce.sh will start php-fpm, not the built-in server
- nginx handles port 80/8443

### 502 Bad Gateway

**Symptom**: Page loads but shows 502 error

**Cause**: nginx cannot connect to PHP-FPM

**Resolution**:
- Verify php-fpm is running: `ps aux | grep php-fpm`
- Check nginx error log
- Ensure `PHP_MODE=fpm` is set

### Blank Page on Port 80

**Symptom**: Port forwarded but nothing serves

**Cause**: Configuration mismatch - nginx not listening on port 80

**Resolution**:
- Ensure nginx config includes `listen 80;` server block
- Rebuild container after config changes

## Development Modes

### Mode 1: PHP Built-in (Default)

```bash
PHP_MODE=builtin PORT=8080
```
- Simple, no nginx
- Good for quick local dev
- Not suitable for production-like testing

### Mode 2: PHP-FPM + nginx

```bash
PHP_MODE=fpm
```
- Uses nginx sidecar
- Production-like architecture
- SSL on 8443

### Mode 3: Codespaces

- Automatically uses nginx sidecar
- GitHub handles SSL termination
- Access via https://{codespace}-{port}.app.github.dev/
