# DevOps Sandbox Platform — Makefile
# Usage: make <target>

.PHONY: up down create destroy logs health simulate clean status

# ── Start everything ──────────────────────────────────────────────────────────
up:
	@echo "🚀 Starting DevOps Sandbox Platform..."
	@# Start Nginx if not running
	@docker ps | grep -q sandbox-nginx || docker run -d \
		--name sandbox-nginx \
		--restart unless-stopped \
		-p 80:80 \
		-v $(PWD)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
		-v $(PWD)/nginx/conf.d:/etc/nginx/conf.d \
		-v $(PWD)/logs:/var/log/nginx \
		nginx:latest
	@# Start cleanup daemon
	@mkdir -p logs envs
	@nohup bash platform/cleanup_daemon.sh > logs/cleanup.log 2>&1 &
	@echo "$$!" > logs/daemon.pid
	@# Start health poller
	@nohup bash monitor/health_poller.sh > logs/health_poller.log 2>&1 &
	@echo "$$!" > logs/poller.pid
	@# Start API
	@nohup python3 platform/api.py > logs/api.log 2>&1 &
	@echo "$$!" > logs/api.pid
	@echo "✅ Platform is up!"
	@echo "   API:      http://75.101.201.134:5001"
	@echo "   Nginx:    http://75.101.201.134:80"
	@echo "   Docs:     make help"

# ── Stop everything ───────────────────────────────────────────────────────────
down:
	@echo "🛑 Stopping DevOps Sandbox Platform..."
	@# Stop all environments
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ENV_ID=$$(jq -r '.id' "$$f"); \
		bash platform/destroy_env.sh "$$ENV_ID" 2>/dev/null || true; \
	done
	@# Stop background processes
	@[ -f logs/daemon.pid ] && kill $$(cat logs/daemon.pid) 2>/dev/null || true
	@[ -f logs/poller.pid ] && kill $$(cat logs/poller.pid) 2>/dev/null || true
	@[ -f logs/api.pid ] && kill $$(cat logs/api.pid) 2>/dev/null || true
	@rm -f logs/daemon.pid logs/poller.pid logs/api.pid
	@# Stop Nginx
	@docker stop sandbox-nginx 2>/dev/null || true
	@docker rm sandbox-nginx 2>/dev/null || true
	@echo "✅ Platform stopped!"

# ── Create new environment ────────────────────────────────────────────────────
create:
	@read -p "Environment name: " name; \
	read -p "TTL in seconds (default 1800): " ttl; \
	ttl=$${ttl:-1800}; \
	bash platform/create_env.sh "$$name" "$$ttl"

# ── Destroy specific environment ──────────────────────────────────────────────
destroy:
	@[ -z "$(ENV)" ] && echo "❌ Usage: make destroy ENV=env-abc123" && exit 1 || true
	@bash platform/destroy_env.sh $(ENV)

# ── Tail environment logs ─────────────────────────────────────────────────────
logs:
	@[ -z "$(ENV)" ] && echo "❌ Usage: make logs ENV=env-abc123" && exit 1 || true
	@[ -f logs/$(ENV)/app.log ] && tail -f logs/$(ENV)/app.log || \
	 [ -f logs/archived/$(ENV)/app.log ] && tail -f logs/archived/$(ENV)/app.log || \
	 echo "❌ No logs found for $(ENV)"

# ── Show all env health statuses ──────────────────────────────────────────────
health:
	@echo "🏥 Environment Health Status"
	@echo "================================"
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ENV_ID=$$(jq -r '.id' "$$f"); \
		NAME=$$(jq -r '.name' "$$f"); \
		STATUS=$$(jq -r '.status' "$$f"); \
		PORT=$$(jq -r '.port' "$$f"); \
		HTTP=$$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:$$PORT/health 2>/dev/null); \
		echo "  $$NAME ($$ENV_ID): status=$$STATUS http=$$HTTP"; \
	done
	@echo "================================"

# ── Simulate outage ───────────────────────────────────────────────────────────
simulate:
	@[ -z "$(ENV)" ] && echo "❌ Usage: make simulate ENV=env-abc123 MODE=crash" && exit 1 || true
	@[ -z "$(MODE)" ] && echo "❌ Usage: make simulate ENV=env-abc123 MODE=crash" && exit 1 || true
	@bash platform/simulate_outage.sh --env $(ENV) --mode $(MODE)

# ── Wipe all state, logs, archives ───────────────────────────────────────────
clean:
	@echo "🧹 Cleaning all state and logs..."
	@$(MAKE) down 2>/dev/null || true
	@rm -rf logs/* envs/*
	@mkdir -p logs/archived
	@echo "✅ Clean complete!"

# ── Show platform status ──────────────────────────────────────────────────────
status:
	@echo "📊 Platform Status"
	@echo "================================"
	@echo "Containers:"
	@docker ps --filter "name=sandbox" --format "  {{.Names}}: {{.Status}}"
	@echo ""
	@echo "Active Environments:"
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ENV_ID=$$(jq -r '.id' "$$f"); \
		NAME=$$(jq -r '.name' "$$f"); \
		STATUS=$$(jq -r '.status' "$$f"); \
		EXPIRES=$$(jq -r '.expires_at' "$$f"); \
		echo "  $$NAME ($$ENV_ID): $$STATUS expires=$$EXPIRES"; \
	done
	@echo "================================"

# ── Help ──────────────────────────────────────────────────────────────────────
help:
	@echo "DevOps Sandbox Platform — Available Commands"
	@echo "============================================="
	@echo "  make up                    Start Nginx + daemon + API"
	@echo "  make down                  Stop everything"
	@echo "  make create                Create new environment"
	@echo "  make destroy ENV=<id>      Destroy specific environment"
	@echo "  make logs ENV=<id>         Tail environment logs"
	@echo "  make health                Show all env health statuses"
	@echo "  make simulate ENV=<id> MODE=<mode>  Simulate outage"
	@echo "  make clean                 Wipe all state and logs"
	@echo "  make status                Show platform status"
	@echo "============================================="
	@echo "  Outage modes: crash, pause, network, recover"
