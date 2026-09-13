# Security and production-readiness review

## 1. Secrets and environment configuration

* Risk and evidence: Database credentials are supplied through environment variables rather than being hard-coded in the Docker image or application source. The local `.env` file is excluded from Git.
* Impact: Committing database credentials could expose access to the database and make credential rotation difficult.
* Implemented fix / commit: Database configuration uses `POSTGRES_PASSWORD` from the environment; no database password is stored in the Dockerfile or application source.
* Production follow-up: Use a dedicated secrets manager such as Docker secrets, Vault, or a cloud secret-management service instead of plain environment variables where appropriate.
* How to verify: Search the repository for passwords and inspect the built image for environment files or secret values.

## 2. Public port exposure

* Risk and evidence: Only NGINX publishes a host port. PostgreSQL and Redis are not published to the host and are connected only to the backend network.
* Impact: Exposing database or Redis ports would allow unnecessary external access to internal services.
* Implemented fix / commit: PostgreSQL and Redis have no host port mappings; NGINX is the only published service. `ee2b9cb` — Fix persistence, network isolation, and backend failover.
* Production follow-up: Bind public services to the required interfaces only and place the reverse proxy behind a firewall or cloud security group.
* How to verify: Run `docker compose ps` and inspect the published ports. Confirm PostgreSQL and Redis have no host mappings.

## 3. Container runs as non-root

* Risk and evidence: The application image creates a dedicated `app` user with UID/GID `10001` and runs the application using that user.
* Impact: Running as root could increase the impact of an application compromise or container vulnerability.
* Implemented fix / commit: `e28cf52` — Improve Docker setup and service configuration.
* Production follow-up: Use a read-only root filesystem where practical and drop unnecessary Linux capabilities.
* How to verify: Run `docker exec app-01 id` and confirm the process is not running as root.

## 4. Container image selection and reproducibility

* Risk and evidence: The Python, PostgreSQL, Redis, and NGINX images are pinned to SHA256 digests.
* Impact: Mutable image tags can change between builds, making deployments less reproducible and potentially introducing unexpected changes.
* Implemented fix / commit: `e28cf52` — Improve Docker setup and service configuration.
* Production follow-up: Regularly scan images for vulnerabilities and update pinned digests through a controlled dependency-update process.
* How to verify: Inspect `Dockerfile` and `docker-compose.yml` and confirm images include SHA256 digests.

## 5. Network isolation

* Risk and evidence: The stack separates `frontend` and `backend` networks, with the backend network marked as internal. NGINX is not connected directly to the backend network.
* Impact: Poor network isolation could allow unnecessary service-to-service access and increase the attack surface.
* Implemented fix / commit: `ee2b9cb` — Fix persistence, network isolation, and backend failover.
* Production follow-up: Apply stricter network policies and service-specific access controls in the production platform.
* How to verify: Run `docker network inspect` and confirm PostgreSQL and Redis are only connected to the backend network and NGINX is only on the frontend network.

## 6. Database and Redis persistence

* Risk and evidence: PostgreSQL and Redis use named volumes. Redis also has AOF persistence enabled.
* Impact: Without persistent storage, container recreation could result in data loss.
* Implemented fix / commit: `ee2b9cb` — Fix persistence, network isolation, and backend failover.
* Production follow-up: Use durable production storage with defined retention, replication, and disaster-recovery policies.
* How to verify: Write test data, recreate the relevant container, and verify that the data remains available.

## 7. Backup and restore capability

* Risk and evidence: PostgreSQL backups are created using `pg_dump` in custom format, and `restore.sh` restores and verifies database records.
* Impact: Persistence alone does not protect against accidental deletion, corruption, or loss of the underlying volume.
* Implemented fix / commit: `b4c572d` — Implement PostgreSQL backup and restore.
* Production follow-up: Store backups outside the host, encrypt them, define retention policies, and automate scheduled backups with monitoring.
* How to verify: Run `backup.sh`, inspect the backup with `pg_restore -l`, then run `restore.sh` and verify restored records.

## 8. Logging and monitoring

* Risk and evidence: The project includes NGINX access/error logs and application logs, and the historical incident requires correlation between these sources.
* Impact: Without centralized logging and monitoring, failures can be difficult to detect, correlate, and investigate.
* Implemented fix / commit: Historical logs and the required `log_analysis.md` investigation provide evidence for incident analysis.
* Production follow-up: Send logs to centralized storage, add metrics and alerts for error rates, latency, retries, health-check failures, and dependency failures.
* How to verify: Generate a controlled request/failure and confirm that the relevant application and proxy logs contain enough information to correlate the event.

## 9. Backend availability and failover

* Risk and evidence: NGINX uses two application instances and retries another upstream when the selected backend fails.
* Impact: Without failover, failure of one application container could directly cause client-facing errors.
* Implemented fix / commit: `ee2b9cb` — Fix persistence, network isolation, and backend failover.
* Production follow-up: Add monitoring for backend health, retry rates, latency, and capacity, and use automated scaling where required.
* How to verify: Stop one application instance and send repeated requests through NGINX. Confirm that requests continue to succeed through the remaining healthy instance.

## 10. Resource exhaustion

* Risk and evidence: CPU and memory limits are configured for the application, PostgreSQL, Redis, and NGINX containers.
* Impact: An overloaded or misbehaving container could otherwise consume excessive host resources and affect other services.
* Implemented fix / commit: `e28cf52` — Improve Docker setup and service configuration.
* Production follow-up: Tune resource limits using production metrics and configure alerts for CPU, memory, disk, and container restarts.
* How to verify: Inspect the Compose configuration and container resource settings, then monitor actual resource consumption under representative load.
