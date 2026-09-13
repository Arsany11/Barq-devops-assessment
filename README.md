<img src="assets/barq-logo.svg" alt="BARQ Systems" width="180">

# BARQ Systems — DevOps Assessment

> A repaired and validated Docker Compose environment for the BARQ Systems DevOps internship assessment.

The environment consists of a Flask application running behind NGINX, with PostgreSQL and Redis as backend services.

## Architecture

### Current pre-video state

- NGINX exposed on `127.0.0.1:8080`
- Two Flask instances: `app-01` and `app-02`
- Flask listens internally on `:8080`
- PostgreSQL on `:5432`
- Redis on `:6379`
- Frontend and internal backend Docker networks
- PostgreSQL persistent storage
- Redis persistent storage with AOF
- NGINX load balancing and backend failover

The recorded challenge changes the public port from `8080` to `8090` and adds `app-03`.

See [architecture.png](architecture.png) for the final architecture diagram.

## Prerequisites

- Linux or WSL2
- Python 3.12
- Git
- Docker with Docker Compose
- Docker Desktop using Linux containers when running on Windows

Check the installed versions:

```bash
docker version
docker compose version
python3 --version
git --version
```

## Setup

### Clone and inspect the repository

```bash
git clone <repository-url>
cd BARQ-Academy

git status
git log -2 --oneline
```

### Create the local environment file

```bash
cp .env.example .env
```

The `.env` file is local configuration and must not be committed.

### Change the public port or add an application instance

To change the public port, edit `PUBLIC_PORT` in `.env`:

```dotenv
PUBLIC_PORT=8080
```

Recreate NGINX so Docker applies the new port mapping:

```bash
docker compose -p barq-assessment up -d --force-recreate nginx
```

To add another application instance, add a new service such as `app-xx` to
`docker-compose.yml`, give it a unique `INSTANCE_ID`, and add the instance to
the `application_pool` in `nginx/nginx.conf`:

```nginx
server app-xx:8080 max_fails=0;
```

Also add the new service to NGINX's `depends_on` list when it uses a
healthcheck. Then start the new service and recreate NGINX to load the updated
upstream configuration:

```bash
docker compose -p barq-assessment up -d app-xx
docker compose -p barq-assessment up -d --force-recreate nginx
```

Use the new service name in place of `app-xx`.

## Build and Start

Start the environment:

```bash
docker compose -p barq-assessment up --build -d
```

Check the containers:

```bash
docker compose -p barq-assessment ps -a
```

View service logs:

```bash
docker compose -p barq-assessment logs --no-color
```

Follow the logs:

```bash
docker compose -p barq-assessment logs -f --no-color
```

## API Tests

The current public endpoint is `http://127.0.0.1:8080`.

Test the required endpoints:

```bash
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/ready
curl http://127.0.0.1:8080/records
curl http://127.0.0.1:8080/counter
```

Check which application instance handled a request:

```bash
curl http://127.0.0.1:8080/instance
```

Repeat the request to observe traffic reaching both application instances:

```bash
for i in {1..10}; do
    curl -s http://127.0.0.1:8080/instance
    echo
done
```

## Validation

Run the environment validation script:

```bash
python3 validate.py
```

The validation checks:

- Service health
- API endpoints
- Application instance traffic
- Network isolation
- Published host ports

## Failure Test

The failure test stops one application instance, sends traffic through NGINX, verifies that traffic continues, then restores the stopped instance.

```bash
./failure_test.py
```

The script uses bounded waits and exits with a non-zero status if failover or recovery cannot be verified.

## Persistence Test

Create a record:

```bash
curl -X POST http://127.0.0.1:8080/records \
  -H "Content-Type: application/json" \
  -d '{"name":"persistence-test"}'
```

Verify the record:

```bash
curl http://127.0.0.1:8080/records
```

Recreate the application containers without removing persistent data:

```bash
docker compose -p barq-assessment up -d --force-recreate app-01 app-02
```

Verify the record again:

```bash
curl http://127.0.0.1:8080/records
```

PostgreSQL uses persistent storage mounted at `/var/lib/postgresql/data`.

Redis uses persistent storage mounted at `/data` with Redis AOF enabled.

## Backup

Create a PostgreSQL backup:

```bash
./backup.sh
```

The backup is written to `.local-backups/`.

Backups are local assessment artifacts and must not be committed.

## Restore

Restore a PostgreSQL backup:

```bash
./restore.sh <backup-file>
```

The restore script verifies that records exist after restoration.

## App-Only Tests

The application tests can be run without starting the full Docker environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
deactivate
```

## Stop and Cleanup

Stop the services:

```bash
docker compose -p barq-assessment stop
```

Remove the containers and networks:

```bash
docker compose -p barq-assessment down
```

Remove the containers and persistent volumes when the lab is no longer needed:

```bash
docker compose -p barq-assessment down -v
```

> Do not use `docker system prune`, global cleanup commands, or remove unrelated containers.

## Recorded Challenge

The supplied challenge script must be run once and for the first time during the continuous video recording.

> Do not run it before recording.

```bash
./video_challenge.sh
```

During the challenge:

- Diagnose and fix the runtime fault.
- Do not use `docker compose down` to reset the environment.
- Change the public port from `8080` to `8090`.
- Add a third application instance, `app-03`.
- Verify NGINX works on port `8090`.
- Verify all three application instances receive traffic.
- Rerun the validation and failure tests.

The final submitted repository must match the final state demonstrated in the video.

## Documentation

- [Assessment task](assessment/TASK.md)
- [Application contract](assessment/APPLICATION.md)
- [Troubleshooting journal](troubleshooting.md)
- [Log analysis](log_analysis.md)
- [Technical decisions](decisions.md)
- [Security review](security_review.md)
- [AI usage disclosure](AI_USAGE.md)
- [Architecture documentation](docs/ARCHITECTURE.md)
- [Evidence index](docs/EVIDENCE_INDEX.md)

## Repository Structure

```text
.
├── app/
├── assessment/
├── database/
├── docs/
├── logs/
├── nginx/
├── scripts/
├── .github/
├── architecture.png
├── Dockerfile
├── docker-compose.yml
├── validate.py
├── failure_test.py
├── backup.sh
├── restore.sh
└── README.md
```

## Security and Operational Notes

The assessment environment is intended for local use only.

- Do not commit `.env` or real secrets.
- Only NGINX publishes a host port.
- PostgreSQL and Redis are isolated on the internal backend network.
- The Flask container runs as a non-root user.
- Container images are pinned by digest.
- PostgreSQL and Redis use persistent storage.
- Redis persistence uses AOF.
- CPU and memory limits are configured for the services.
- NGINX provides backend failover.

Production deployments should use a secrets manager, centralized logging, monitoring, alerting, and appropriate backup storage.

See [security_review.md](security_review.md) for the detailed security review.
