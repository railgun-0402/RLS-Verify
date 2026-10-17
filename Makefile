# ローカル既定値。AWS では make <target> PG_HOST=... PG_SSLMODE=require ... で上書きする
PG_HOST        ?= localhost
PG_SSLMODE     ?= disable
PG_ADMIN_USER  ?= postgres
PG_ADMIN_PASS  ?= postgres
APP_DB_PASSWORD   ?= app_pass
BATCH_DB_PASSWORD ?= batch_pass

PG_ADMIN_URL = postgres://$(PG_ADMIN_USER):$(PG_ADMIN_PASS)@$(PG_HOST):5432/rlsdemo?sslmode=$(PG_SSLMODE)
PG_APP_URL   = postgres://app_user:$(APP_DB_PASSWORD)@$(PG_HOST):5432/rlsdemo?sslmode=$(PG_SSLMODE)
PG_BATCH_URL = postgres://batch_user:$(BATCH_DB_PASSWORD)@$(PG_HOST):5432/rlsdemo?sslmode=$(PG_SSLMODE)

PSQL_ADMIN = psql "$(PG_ADMIN_URL)" -v ON_ERROR_STOP=1 \
             -v app_password="$(APP_DB_PASSWORD)" -v batch_password="$(BATCH_DB_PASSWORD)"

.PHONY: up down migrate policy-org-only policy-membership stage1 stage2 stage3 stage4 run scenarios mysql-demo

up:
	docker compose up -d postgres
	@echo "waiting for postgres..."; sleep 3

down:
	docker compose --profile mysql down -v

migrate:
	@for f in db/migrations/*.sql; do echo ">> $$f"; $(PSQL_ADMIN) -q -f $$f || exit 1; done
	$(MAKE) policy-org-only

policy-org-only:
	$(PSQL_ADMIN) -q -f db/policies/org_only.sql
	@echo "donations_tenant = パターンA（大学IDのみ）"

policy-membership:
	$(PSQL_ADMIN) -q -f db/policies/with_membership.sql
	@echo "donations_tenant = パターンB（大学ID + 所属）"

stage1:
	psql "$(PG_APP_URL)" -f db/verify/stage1_rls.sql

stage2:
	psql "$(PG_APP_URL)" -f db/verify/stage2_set_local.sql

stage3:
	cd go && DATABASE_URL="$(PG_APP_URL)" go run ./cmd/stage3

stage4:
	cd go && DATABASE_URL="$(PG_APP_URL)" BATCH_DATABASE_URL="$(PG_BATCH_URL)" go run ./cmd/stage4

run:
	cd go && DATABASE_URL="$(PG_APP_URL)" go run ./cmd/api

scenarios:
	./scripts/scenarios.sh

mysql-demo:
	docker compose --profile mysql up -d mysql
	@echo "waiting for mysql..."; until docker compose exec -T mysql mysqladmin ping -uroot -proot --silent; do sleep 2; done
	docker compose exec -T mysql mysql -uroot -proot --default-character-set=utf8mb4 --force -t rlsdemo < mysql/why_rls_is_hard.sql
