#!/usr/bin/env python3
"""Candidate deliverable: stop one backend, measure traffic, restore it and verify."""
#!/usr/bin/env python3
"""Test backend failure, continued availability, and recovery."""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

def public_url():
    configured_url = os.getenv("PUBLIC_URL")
    if configured_url:
        return configured_url.rstrip("/")

    try:
        result = subprocess.run(
            ["docker", "compose", "port", "nginx", "80"],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )
        published_address = result.stdout.strip().splitlines()[0]
        port = published_address.rsplit(":", 1)[1]
    except (IndexError, subprocess.SubprocessError, subprocess.TimeoutExpired):
        port = os.getenv("PUBLIC_PORT", "8080")

    return f"http://127.0.0.1:{port}"


PUBLIC_URL = public_url()
BACKEND = os.getenv("BACKEND_TO_STOP", "app-02")
REQUEST_COUNT = int(os.getenv("REQUEST_COUNT", "10"))
WAIT_TIMEOUT = 30


def run_command(*args):
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=15,
    )


def container_is_healthy(service):
    result = run_command(
        "docker", "compose", "ps",
        "--format", "{{.Service}} {{.Status}}"
    )

    for line in result.stdout.splitlines():
        service_name, _, status = line.partition(" ")
        if service_name == service:
            return "(healthy)" in status

    return False


def wait_for_healthy(service):
    deadline = time.time() + WAIT_TIMEOUT

    while time.time() < deadline:
        if container_is_healthy(service):
            return True
        time.sleep(1)

    return False


def request(path):
    try:
        with urllib.request.urlopen(
            f"{PUBLIC_URL}{path}",
            timeout=5,
        ) as response:
            body = response.read().decode()
            return response.status, body

    except urllib.error.HTTPError as exc:
        return exc.code, ""

    except (urllib.error.URLError, TimeoutError):
        return None, ""


def get_instance():
    status, body = request("/instance")

    if status != 200:
        return None

    try:
        data = json.loads(body)
        return data.get("instance_id")
    except json.JSONDecodeError:
        return None


def main():
    print("=== Backend failure and recovery test ===")
    print(f"Public URL: {PUBLIC_URL}")
    print(f"Backend to stop: {BACKEND}")
    print(f"Requests during failure: {REQUEST_COUNT}")
    print()

    if not container_is_healthy(BACKEND):
        print(f"FAIL: {BACKEND} is not healthy before the test.")
        return 1

    stopped = False
    test_passed = False

    try:
        result = run_command(
            "docker", "compose", "stop", BACKEND
        )

        if result.returncode != 0:
            print(f"FAIL: Could not stop {BACKEND}.")
            print(result.stderr.strip())
            return 1

        stopped = True
        print(f"PASS: Stopped {BACKEND}.")

        time.sleep(2)

        successes = 0
        errors = 0

        for _ in range(REQUEST_COUNT):
            status, _ = request("/health")

            if status == 200:
                successes += 1
            else:
                errors += 1

        print(
            f"Failure window: "
            f"{successes} successful request(s), "
            f"{errors} error(s)."
        )

        if successes == 0:
            print("FAIL: No traffic reached a healthy backend.")
            return 1

        print("PASS: Traffic continued while one backend was stopped.")

        test_passed = True

    finally:
        if stopped:
            print(f"Restarting {BACKEND}...")

            result = run_command(
                "docker", "compose", "start", BACKEND
            )

            if result.returncode != 0:
                print(f"FAIL: Could not restart {BACKEND}.")
                print(result.stderr.strip())
                test_passed = False

    if not test_passed:
        return 1

    if not wait_for_healthy(BACKEND):
        print(
            f"FAIL: {BACKEND} did not become healthy "
            f"within {WAIT_TIMEOUT} seconds."
        )
        return 1

    print(f"PASS: {BACKEND} recovered and became healthy.")

    instances = set()

    for _ in range(REQUEST_COUNT):
        instance = get_instance()

        if instance:
            instances.add(instance)

    print(f"Instances seen after recovery: {sorted(instances)}")

    if BACKEND not in instances:
        print(
            f"FAIL: Recovered backend {BACKEND} "
            "did not serve requests."
        )
        return 1

    print(f"PASS: Recovered backend {BACKEND} served requests.")
    print()
    print("Failure and recovery test passed.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
