# Troubleshooting journal

Keep chronological entries. Copy this block for each meaningful investigation.

## Entry 1 / Initial environment investigation

- Symptom: After starting the stack, both `app-01` and `app-02` were running Docker but showed as unhealthy.
- Hypothesis: I first suspected that the Flask applications were not starting correctly or that the healthcheck was using the wrong endpoint.
- Command or test: I checked the container status and logs, then tested the application directly from inside the containers.
- Actual output: Both applications were running on `127.0.0.1:8080`. The `/health` endpoint returned HTTP 200, but the Docker healthcheck was requesting `/healthz`, which does not exist and returned HTTP 404.
- Failed attempt and what changed your thinking: There was no failed fix at this point. Testing `/health` directly showed that the application itself was working, so I focused on the healthcheck configuration.
- Root cause: The Docker healthcheck was configured to use `/healthz`, while the Flask application provides `/health`.
- Fix: Changed the Docker healthcheck to call /health.
- Retest evidence: Direct request to `/health` returned HTTP 200 from both application containers.
- Related commit: eb9b030 — Fix dependency ports and application healthcheck
- Remaining uncertainty: None for this issue. The application healthcheck was working correctly after the fix.

## Entry 2 / Dependency readiness investigation

- Symptom: The `/ready` endpoint returned HTTP 503 and reported that both PostgreSQL and Redis were unavailable.
- Hypothesis: I suspected that PostgreSQL or Redis might not be running or that the applications could not reach them.
- Command or test: I checked the PostgreSQL and Redis container status and tested connectivity from `app-01` to `postgres:5432` and `redis:6379`. I also checked the environment variables inside the application container.
- Actual output: Both PostgreSQL and Redis were healthy and reachable from `app-01`. However, the application was configured to use `postgres:5433` and `redis:6380`, while the services were actually listening on their normal internal ports `5432` and `6379`.
- Failed attempt and what changed your thinking: The connectivity test ruled out a Docker networking problem. This changed my focus to the application configuration.
- Root cause: The internal database and Redis ports in `config/app.env` were incorrect.
- Fix: Changed the PostgreSQL port to `5432` and the Redis port to `6379`.
- Retest evidence: After correcting the ports, `/ready` returned HTTP 200 and reported PostgreSQL and Redis as ready.
- Related commit: `eb9b030` — Fix dependency ports and application healthcheck.
- Remaining uncertainty: None for the dependency port issue.

## Entry 3 / Backend identity investigation

- Symptom: When checking the two application `instances`, both `app-01` and `app-02` reported the instance ID as `app-01`.
- Hypothesis: I suspected that the instance ID might be configured incorrectly in Docker Compose.
- Command or test: I called the `/instance` endpoint directly on both containers and then checked their `INSTANCE_ID` values configured for `app-01` and `app-02` in `docker-compose.yml`.
- Actual output: `app-01` correctly reported `app-01`, but `app-02` also reported `app-01`. The Compose configuration showed that `app-02` had `INSTANCE_ID: "app-01"`.
- Failed attempt and what changed your thinking: There was no failed fix. Testing the containers directly showed that the problem was inside the application configuration and not related to NGINX load balancing.
- Root cause: `app-02` was configured with the same `INSTANCE_ID` as `app-01`.
- Fix: Changed the INSTANCE_ID for app-02 to app-02.
- Retest evidence: Requests to `/instance` correctly identified the two backend instances as `app-01` and `app-02`.
- Related commit: `e899db7`—Fix NGINX routing and backend connectivity
- Remaining uncertainty: None for the instance identity configuration.

## Entry 4 / NGINX connectivity investigation

- Symptom: Requests to `http://127.0.0.1:8080` failed with `Recv failure: Connection reset by peer`.
- Hypothesis: I suspected there was a port or upstream configuration problem between the host, NGINX, and the Flask applications.
- Command or test: I checked the Docker port mapping, the port NGINX was listening on, the NGINX upstream configuration, and the address/port used by the Flask applications.
- Actual output: Docker mapped host port `8080` to NGINX port `81`, but NGINX was listening on port `80`. The upstream also used `app-01:8081` while the applications were running on port `8080`. In addition, the Flask applications were bound to `127.0.0.1`, which prevents NGINX from reaching them through the Docker network.
- Failed attempt and what changed your thinking: Testing the Flask `/health` endpoint directly from inside the containers worked, which showed that the applications themselves were running. This helped isolate the problem to the NGINX and Docker networking configuration.
- Root cause: There are multiple connectivity configuration errors: the host-to-NGINX port mapping does not match the NGINX listening port, one NGINX upstream port is incorrect, and the Flask applications are bound only to localhost.
- Fix: Changed the NGINX container to listen on port `80`, corrected the upstream application port to `8080`, and changed the application binding to `0.0.0.0` so NGINX could reach the applications through the Docker network.
- Retest evidence: Requests through `http://127.0.0.1:8080` successfully reached the application through NGINX, and requests to `/instance` showed traffic reaching the backend instances.
- Related commit: `e899db7` — Fix NGINX routing and backend connectivity.
- Remaining uncertainty: None for the initial NGINX connectivity issue.

## Entry 5 / NGINX backend failover investigation

- Symptom: After stopping `app-01`, requests through NGINX did not consistently continue to the remaining `app-02` instance. Some requests returned HTTP 504.
- Hypothesis: I suspected that NGINX was not retrying another upstream when the first backend became unavailable.
- Command or test: I stopped `app-01` and sent repeated requests to the public `/health` endpoint through NGINX. I then checked the NGINX configuration and logs.
- Actual output: With `app-01` stopped, some requests returned HTTP 200 while others returned HTTP 504. The NGINX configuration had `proxy_next_upstream off`, so NGINX did not retry `app-02` after an upstream failure.
- Failed attempt and what changed your thinking: The first failover test did not give continuous successful responses. Checking the NGINX configuration showed that upstream retrying had been explicitly disabled.
- Root cause: NGINX was configured with `proxy_next_upstream off`, preventing it from trying the other healthy backend after an upstream failure.
- Fix: Changed `proxy_next_upstream` to retry on `error`, `timeout`, `http_502`, `http_503`, and `http_504`.
- Retest evidence: With `app-01` stopped, 10 consecutive requests to `/health` returned HTTP 200 from `app-02`. After restarting `app-01`, traffic returned to both backend instances.
- Related commit: `ee2b9cb`— Fix persistence, network isolation, and backend failover.
- Remaining uncertainty: None for the tested two-instance failover scenario.
go 

## Entry 6 / PostgreSQL persistence and authentication investigation

- Symptom: After recreating the PostgreSQL container, the application could no longer connect to the database and `/ready` returned HTTP 503.
- Hypothesis: I suspected that the PostgreSQL container might not have started correctly or that the application was using the wrong database connection settings.
- Command or test: I checked the PostgreSQL container status and tested the database connection directly from `app-01` using the application's `DATABASE_URL`. I also checked the PostgreSQL environment and the database configuration.
- Actual output: PostgreSQL was running, but the application connection failed with `password authentication failed for user "barq_app"`. The named PostgreSQL volume contained an already-initialized database, so the password in the existing database role did not automatically change when the Compose `POSTGRES_PASSWORD` value changed.
- Failed attempt and what changed your thinking: Recreating the PostgreSQL container did not fix the authentication problem because the named volume preserved the existing database state. This showed that the problem was with the persisted database credentials rather than the container itself.
- Root cause: The PostgreSQL data volume was already initialized with a different password for the `barq_app` role. `POSTGRES_PASSWORD` only initializes the password when the database is created; it does not update an existing role on subsequent container recreations.
- Fix: Updated the existing `barq_app` database role password to match the application configuration without deleting the PostgreSQL volume.
- Retest evidence: The application connected successfully to PostgreSQL, `/ready` returned HTTP 200, and database-backed endpoints worked after the password was corrected.
- Related commit: `ee2b9cb`— Fix persistence, network isolation, and backend failover.
- Remaining uncertainty: None for the PostgreSQL authentication issue.

## Entry 7 / Database and Redis persistence investigation

- Symptom: PostgreSQL and Redis were not configured with reliable persistence across container recreation.
- Hypothesis: I suspected that the services were either using the wrong storage configuration or were missing the required persistence settings.
- Command or test: I checked the PostgreSQL and Redis container mounts and persistence settings. I also stored test data, recreated the containers, and checked whether the data remained available.
- Actual output: PostgreSQL's named volume was initially mounted at `/var/lib/postgresql/backup`, while PostgreSQL was using `/var/lib/postgresql/data`. Redis did not have AOF persistence enabled and did not have a named volume mounted at `/data`.
- Failed attempt and what changed your thinking: Recreating the containers showed that container recreation alone was not enough to guarantee persistence. Checking the actual data directories confirmed that the persistent storage was not configured correctly.
- Root cause: PostgreSQL was using the wrong volume mount path, while Redis was missing both persistent storage and AOF persistence.
- Fix: Mounted `postgres-data` at `/var/lib/postgresql/data`, added the `redis-data` volume at `/data`, and enabled Redis AOF with `--appendonly yes`.
- Retest evidence: PostgreSQL data survived container recreation, and Redis test data remained available after recreating the Redis container. Redis also reported AOF enabled and `/data` as its data directory.
- Related commit: `ee2b9cb` — Fix persistence, network isolation, and backend failover.
- Remaining uncertainty: None for the tested PostgreSQL and Redis persistence configuration.

## Entry 8 / Environment validation investigation

- Symptom: The required Docker, Compose, environment, and service configuration checks had to be verified consistently instead of relying only on manual commands.
- Hypothesis: I suspected that a validation script would make the checks repeatable and make failures easier to identify.
- Command or test: I ran the validation script after the Docker and service configuration changes.
- Actual output: The validation checks passed for the application endpoints, backend instances, service health, network isolation, and the published NGINX port.
- Failed attempt and what changed your thinking: No failed attempt was needed for this investigation. The main goal was to make the existing manual checks repeatable.
- Root cause: The starter project did not have a single validation script covering the required runtime checks.
- Fix: Added `validate.py` to perform the required environment and runtime validation checks.
- Retest evidence: Running the validation script completed successfully with all checks passing.
- Related commit: `373046d` — Add environment validation checks.
- Remaining uncertainty: The script covers the checks implemented in it; it does not replace the separate failure, persistence, and backup/restore tests.

## Entry 9 / PostgreSQL backup and restore investigation

- Symptom: The project needed a way to create a PostgreSQL backup and restore the database from that backup.
- Hypothesis: I suspected that the existing database could be backed up using `pg_dump` and restored using `pg_restore`.
- Command or test: I created a PostgreSQL custom-format backup using `pg_dump`, checked the backup with `pg_restore -l`, and tested the restore script against the database.
- Actual output: The backup was created successfully in custom format and contained the expected database objects. The restore script successfully restored the database and verified that records were available.
- Failed attempt and what changed your thinking: I temporarily changed the restore verification query to reference a nonexistent table. The restore operation completed, but the verification step failed as expected. This confirmed that the script was actually checking the restored data instead of only reporting success.
- Root cause: There was no automated backup and restore workflow in the starter project.
- Fix: Added `backup.sh` and `restore.sh` to create and restore PostgreSQL custom-format backups with verification.
- Retest evidence: A backup was created successfully, `pg_restore -l` confirmed its contents, and the restore script successfully verified restored records after the verification query was corrected.
- Related commit: `b4c572d` — Implement PostgreSQL backup and restore.
- Remaining uncertainty: The backup and restore process was tested locally; an automated scheduled backup process is not included.

## Entry 10 / CI PostgreSQL authentication investigation

- Symptom: The GitHub Actions CI workflow failed while starting the Docker Compose services because PostgreSQL became unhealthy.
- Hypothesis: I suspected that the PostgreSQL service was failing to initialize correctly or that the application could not authenticate with the database.
- Command or test: I checked the CI service startup and PostgreSQL diagnostics from the workflow logs.
- Actual output: PostgreSQL was unhealthy because the database password used by the application did not match the password configured for PostgreSQL.
- Failed attempt and what changed your thinking: The initial workflow did not provide `POSTGRES_PASSWORD` in the CI environment. This showed that the workflow could not rely on the local `.env` configuration.
- Root cause: GitHub Actions did not have the local `.env` file, so the PostgreSQL password required by the Compose configuration was not explicitly provided to the CI environment.
- Fix: Added `POSTGRES_PASSWORD: ci_test_password` to the GitHub Actions workflow environment so PostgreSQL and the application use the same password during CI.
- Retest evidence: The CI workflow successfully started the services and completed the validation steps after the password was provided.
- Related commit:  `5cd8196` — Add GitHub Actions CI pipeline. `+` `6d384b4` — Provide CI database password.
 
- Remaining uncertainty: None for the CI PostgreSQL password configuration.
