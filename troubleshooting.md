# Troubleshooting journal

Keep chronological entries. Copy this block for each meaningful investigation.

## Entry 1 / Initial environment investigation

- Symptom: After starting the stack, both `app-01` and `app-02` were running but showed as unhealthy. The public endpoint on port 8080 also was not responding correctly.
- Hypothesis: I first suspected that the Flask applications were not starting correctly or that the healthcheck was pointing to the wrong endpoint.
- Command or test: I checked the container status and logs, then tested the application directly from inside the containers.
- Actual output: Both applications were running on `127.0.0.1:8080`. The `/health` endpoint returned HTTP 200, but the Docker healthcheck was requesting `/healthz`, which does not exist and returned HTTP 404.
- Failed attempt and what changed your thinking: There was no failed fix at this point. Testing `/health` directly showed that the application itself was working, so the problem was with the healthcheck rather than the Flask startup.
- Root cause: The Docker healthcheck was configured to use `/healthz`, while the Flask application provides `/health`.
- Fix: Not applied yet. I recorded the issue first so I can make the change and verify it later.
- Retest evidence: Direct request to `/health` returned HTTP 200 from both application containers.
- Related commit: Not committed yet.
- Remaining uncertainty: I still need to verify the healthcheck after changing it and confirm that both containers become healthy.

## Entry 2 / Dependency readiness investigation

- Symptom: The `/ready` endpoint returned HTTP 503 and reported that both PostgreSQL and Redis were unavailable.
- Hypothesis: I suspected that PostgreSQL or Redis might not be running or that the applications could not reach them.
- Command or test: I checked the PostgreSQL and Redis container status and tested connectivity from `app-01` to `postgres:5432` and `redis:6379`. I also checked the environment variables inside the application container.
- Actual output: Both PostgreSQL and Redis were healthy and reachable from `app-01`. However, the application was configured to use `postgres:5433` and `redis:6380`, while the services were actually listening on their normal internal ports `5432` and `6379`.
- Failed attempt and what changed your thinking: The connectivity test ruled out a Docker networking problem. This changed my focus to the application configuration.
- Root cause: The internal database and Redis ports in `config/app.env` were incorrect.
- Fix: Not applied yet. I recorded the configuration issue before changing it.
- Retest evidence: TCP connections to `postgres:5432` and `redis:6379` succeeded from the application container.
- Related commit: Not committed yet.
- Remaining uncertainty: After correcting the ports, I need to verify that `/ready` returns HTTP 200.

## Entry 3 / Backend identity investigation

- Symptom: When checking the two application instances, both `app-01` and `app-02` reported the instance ID as `app-01`.
- Hypothesis: I suspected that the instance ID might be configured incorrectly in Docker Compose.
- Command or test: I called the `/instance` endpoint directly on both containers and then checked their `INSTANCE_ID` environment configuration in `docker-compose.yml`.
- Actual output: `app-01` correctly reported `app-01`, but `app-02` also reported `app-01`. The Compose configuration showed that `app-02` had `INSTANCE_ID: "app-01"`.
- Failed attempt and what changed your thinking: There was no failed fix. Testing the containers directly showed that the problem was inside the application configuration and not related to NGINX load balancing.
- Root cause: `app-02` was configured with the same `INSTANCE_ID` as `app-01`.
- Fix: Not applied yet. I will change the value to `app-02` during the fix stage.
- Retest evidence: Direct `/instance` testing confirmed the incorrect identity before making any changes.
- Related commit: Not committed yet.
- Remaining uncertainty: I need to verify that requests can correctly identify both instances after the configuration change.

## Entry 4 / NGINX connectivity investigation

- Symptom: Requests to `http://127.0.0.1:8080` failed with `Recv failure: Connection reset by peer`.
- Hypothesis: I suspected there was a port or upstream configuration problem between the host, NGINX, and the Flask applications.
- Command or test: I checked the Docker port mapping, the port NGINX was listening on, the NGINX upstream configuration, and the address/port used by the Flask applications.
- Actual output: Docker mapped host port `8080` to NGINX port `81`, but NGINX was listening on port `80`. The upstream also used `app-01:8081` while the applications were running on port `8080`. In addition, the Flask applications were bound to `127.0.0.1`, which prevents NGINX from reaching them through the Docker network.
- Failed attempt and what changed your thinking: Testing the Flask `/health` endpoint directly from inside the containers worked, which showed that the applications themselves were running. This helped isolate the problem to the NGINX and Docker networking configuration.
- Root cause: There are multiple connectivity configuration errors: the host-to-NGINX port mapping does not match the NGINX listening port, one NGINX upstream port is incorrect, and the Flask applications are bound only to localhost.
- Fix: Not applied yet. I will correct the port and binding configuration during the fix stage.
- Retest evidence: Direct application requests succeeded, while the public NGINX request failed. This confirms that the issue is between NGINX and the applications rather than with Flask startup.
- Related commit: Not committed yet.
- Remaining uncertainty: After fixing the configuration, I need to verify public access through NGINX and confirm that traffic reaches both application instances.
