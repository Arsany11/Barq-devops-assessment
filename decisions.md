# Technical decisions


## Decision 1 / Application base image

- Choice: Use the pinned `python:3.12-slim-bookworm` base image with a specific SHA256 digest.
- Why: Python 3.12 provides the required runtime for the application, while the slim Bookworm image keeps the container relatively lightweight. Pinning the image by digest ensures that the same base image is used across builds instead of depending on a mutable image tag.
- Alternative: Use an unpinned `python:3.12-slim-bookworm` tag or a larger general-purpose Python image.
- Trade-off: Pinning by digest improves reproducibility but requires manually updating the digest when intentionally upgrading the base image or applying base-image security updates.
- Evidence / commit: `Dockerfile` configuration; `e28cf52` — Improve Docker setup and service configuration.
- Production improvement: Use an automated dependency/image scanning process and regularly update the pinned digest through a controlled security update process.

## Decision 2 / Service health checks

- Choice: Use service-specific health checks and make dependent services wait for required services to become healthy.
- Why: Each service is checked using a meaningful endpoint or command. The applications use `/health`, PostgreSQL uses `pg_isready`, Redis uses `redis-cli ping`, and NGINX checks its `/health` endpoint. This allows Docker Compose to distinguish between a running container and a service that is actually ready to handle requests.
- Alternative: Only check whether containers are running, or use a generic TCP port check for every service.
- Trade-off: Health checks add startup delay and periodic container activity, and an overly strict or incorrect health check can incorrectly mark a working service as unhealthy. This happened initially when the application health check used `/healthz`, which did not exist.
- Evidence / commit: Verified in `docker-compose.yml`; `eb9b030` — Fix dependency ports and application healthcheck.
- Production improvement: Separate liveness and readiness checks where appropriate and tune health-check intervals and retries based on actual production startup and dependency behavior.

## Decision 3 / Network isolation

- Choice: Separate the Docker services into `frontend` and `backend` networks, with the `backend` network configured as internal.
- Why: NGINX is the only service exposed to the host, while PostgreSQL and Redis remain isolated from direct external access. The application instances connect to both networks so they can receive traffic from NGINX and communicate with the backend dependencies.
- Alternative: Place all services on one shared Docker network and expose the dependency ports to the host.
- Trade-off: Multiple networks provide better isolation and reduce the exposed attack surface, but they add configuration complexity because each service must be connected only to the networks it actually needs.
- Evidence / commit: Verified in `docker-compose.yml`; `ee2b9cb` — Fix persistence, network isolation, and backend failover.
- Production improvement: Apply stricter network policies at the infrastructure level and use separate credentials and access controls for each service.

## Decision 4 / Timeouts and retries

- Choice: Configure NGINX to retry another upstream when the selected backend fails because of an error, timeout, or HTTP 502/503/504 response.
- Why: The application has two backend instances, so a temporary failure of one instance should not make the client request fail when another healthy instance is available.
- Alternative: Disable upstream retries and return the original upstream failure to the client.
- Trade-off: Retries improve availability, but they can increase request latency and may be unsafe for non-idempotent operations if a request could be processed by the first backend before the retry.
- Evidence / commit: `ee2b9cb` — Fix persistence, network isolation, and backend failover. The failover test produced 10 consecutive successful `/health` responses while `app-01` was stopped.
- Production improvement: Use carefully tuned connect/read timeouts and retry policies based on endpoint idempotency, and monitor retry rates and upstream latency.

## Decision 5 / Restart and resource limits

- Choice: Use `restart: "unless-stopped"` and define CPU and memory limits for each service.
- Why: Restart policies allow services to recover from unexpected container failures, while resource limits prevent a single service from consuming excessive CPU or memory and affecting the rest of the stack.
- Alternative: Use unlimited resources and rely on manual recovery, or allow Docker to restart containers without resource limits.
- Trade-off: Resource limits improve isolation and predictability, but limits that are too restrictive can cause unnecessary failures or reduced performance.
- Evidence / commit: Verified in `docker-compose.yml`; `e28cf52` — Improve Docker setup and service configuration.
- Production improvement: Tune limits using observed resource usage, add monitoring and alerting, and use orchestration features such as health-aware restart and scaling policies where appropriate.

## Decision 6 / Persistent storage

- Choice: Use named Docker volumes for PostgreSQL and Redis. PostgreSQL stores data under `/var/lib/postgresql/data`, while Redis uses `/data` with AOF persistence enabled.
- Why: Container recreation should not remove application data. Redis AOF also provides a durable record of write operations that can be replayed after restart.
- Alternative: Store data only inside the containers or use temporary storage such as `tmpfs`.
- Trade-off: Named volumes preserve data across container recreation but require explicit backup and recovery procedures. Redis AOF adds disk I/O and storage usage.
- Evidence / commit: `ee2b9cb` — Fix persistence, network isolation, and backend failover. PostgreSQL and Redis persistence were also verified through container recreation tests.
- Production improvement: Use managed database/storage services or durable external storage with automated, tested backups, retention policies, and disaster-recovery procedures.

## Decision 7 / Non-root application container

- Choice: Create a dedicated `app` user with UID/GID `10001` and run the application as that user instead of root.
- Why: Running the application without root privileges limits the potential impact of an application compromise or container-level vulnerability.
- Alternative: Run the application as the default root user provided by the base image.
- Trade-off: A non-root container improves security but can require additional permission configuration when the application needs to write files or access system resources.
- Evidence / commit: `Dockerfile` configuration; `e28cf52` — Improve Docker setup and service configuration.
- Production improvement: Use read-only filesystems where practical, drop unnecessary Linux capabilities, and apply additional container security policies.
