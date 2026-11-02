# Nextcloud host
Docker/Podman containers for easy hosting of Nextcloud with nginx-proxy and acme-companion.

## Setup
1. Copy `.env.example` to `.env` and fill in values.
2. Set `PUBLIC_IP` to your public IP address.
3. Set `LETSENCRYPT_EMAIL` for certificate notifications.
4. Ensure ports 80 and 443 are open to the internet (required for HTTP-01 challenge).
5. Data is stored in `/mnt/nextcloud/` by default (create if needed, or change paths in `compose.yml`).
6. For Podman, ensure the Podman API socket is running (e.g. `systemctl --user enable --now podman.socket`) and update the socket paths in `compose.yml` if your UID differs.
7. Start with `podman-compose up -d` or `docker compose up -d`.

Certificates are automatically obtained and renewed via Let's Encrypt using `*.nip.io` (or `*.sslip.io`) for your public IP. Use Let's Encrypt staging first if testing to avoid rate limits (see commented `ACME_CA_URI` in `compose.yml`).
