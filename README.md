# DevOps Sandbox Platform

A self-service platform where users spin up isolated temporary environments, deploy apps, simulate outages, monitor health, and auto-destroy on TTL expiry. Think miniature Heroku with chaos engineering.

## Architecture
## Prerequisites

- Ubuntu 22.04+ Linux VM
- Docker 29+
- Python 3 + Flask
- curl, jq

## Quick Start (5 commands)

```bash
git clone https://github.com/vames1/devops-sandbox.git
cd devops-sandbox
docker build -t sandbox-app:latest app/
make up
make create
```

## Full Demo Walkthrough

```bash
# 1. Start platform
make up

# 2. Create environment
make create
# Enter name: myapp
# Enter TTL: 300

# 3. Check health
make health

# 4. Simulate outage
make simulate ENV=env-abc123 MODE=crash

# 5. Observe degraded status
make health

# 6. Recover
make simulate ENV=env-abc123 MODE=recover

# 7. Auto-destroy (wait for TTL) or manual:
make destroy ENV=env-abc123
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /envs | Create environment |
| GET | /envs | List all environments |
| DELETE | /envs/:id | Destroy environment |
| GET | /envs/:id/logs | Last 100 lines of logs |
| GET | /envs/:id/health | Last 10 health checks |
| POST | /envs/:id/outage | Trigger simulation |

## Outage Modes

- `crash` — kills the container
- `pause` — freezes the container
- `network` — disconnects from network
- `recover` — restores everything

## Known Limitations

- Single VM only — not distributed
- Log shipping uses Approach A (simple docker logs)
- No Prometheus/Grafana (optional extras not implemented)
- Port range limited to 32000-33000

## Server

- **IP:** 75.101.201.134
- **API:** http://75.101.201.134:5001
- **Nginx:** http://75.101.201.134:80

## GitHub

https://github.com/vames1/devops-sandbox
