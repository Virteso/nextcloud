# Nextcloud host
Docker/Podman containers for easy hosting of Nextcloud

## Setup
1. Copy `.env.example` to `.env` and fill in values.
2. Set `PUBLIC_IP` to your public IP address (required for Let's Encrypt via nip.io).
3. Set `LETSENCRYPT_EMAIL` for certificate notifications.
4. Ensure ports 80 and 443 are open to the internet (required for HTTP-01 challenge).
5. Data is stored in `/mnt/nextcloud/` by default (create if needed, or change paths in `compose.yml`).
6. Start with `podman-compose up -d` or `docker compose up -d`.

The nginx container will automatically request a Let's Encrypt certificate using your public IP via `*.nip.io` on first run.
