#!/usr/bin/env python3
"""Candidate deliverable: implement environment validation; this is not a solution."""
"""Validate the BARQ assessment environment."""
import time
import sys
import urllib.request
import urllib.error
import json
import subprocess
failures = 0

def check(name, condition):
    global failures
    
    if condition:
        print(f"PASS: {name}")
    else:
        print(f"FAIL: {name}")
        failures += 1
        
def http_check(path, expected_status=200):
    try:
        with urllib.request.urlopen(
            f"http://localhost:8090{path}",
            timeout=3,
        ) as response:
            return response.status == expected_status
    except (urllib.error.URLError, TimeoutError):
        return False
    
def get_instance():
    try:
        with urllib.request.urlopen(
            "http://localhost:8090/instance",
            timeout=3,
        ) as response:
            data = json.loads(response.read().decode())
            return data.get("instance_id")
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None
    
def service_is_healthy(service):
    try:
        result = subprocess.run(
            [
                "docker",
                "compose",
                "ps",
                "--format",
                "{{.Service}} {{.Status}}",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True
        )
        for line in result.stdout.splitlines():
            if line.startswith(f"{service}"):
                return "(healthy)" in line
            
        return False
    except (subprocess.SubprocessError, subprocess.TimeoutExpired):
        return False
    
def nginx_is_not_on_backend():
    try:
        result = subprocess.run(
            [
                "docker",
                "network",
                "inspect",
                "barq-assessment_backend",
                "--format",
                "{{range .Containers}}{{.Name}}{{\"\\n\"}}{{end}}",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )
        
        return "nginx" not in result.stdout.splitlines()
    except (subprocess.SubprocessError, subprocess.TimeoutExpired):
        return False
    
def only_nginx_has_published_port():
    try:
        result = subprocess.run(
            [
                "docker",
                "compose",
                "ps",
                "--format",
                "{{.Service}} {{.Ports}}",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )
        
        for line in result.stdout.splitlines():
            service,_,ports = line.partition(" ")
            
            if service != "nginx" and "->" in ports:
                return False
            
        return True
    except (subprocess.SubprocessError, subprocess.TimeoutExpired):
        return False
    
def wait_for_nginx(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if http_check("/health"):
            return True
        time.sleep(1)
    return False

def main():
    check("Validation script runs", True)
    check("NGINX becomes ready", wait_for_nginx())
    check("PostgreSQL container is healthy", service_is_healthy("postgres"))
    check("Redis container is healthy", service_is_healthy("redis"))
    for endpoint in ["/", "/health", "/ready", "/instance", "/records", "/counter"]:
        check(f"{endpoint} returns 200", http_check(endpoint))
    
    instances = {get_instance() for _ in range(10)}
    check(
        "Both application instances receive traffic",
        {"app-01", "app-02"}.issubset(instances),
    )
    check(
        "NGINX is isolated from the backend network",
        nginx_is_not_on_backend()
        )
    check(
        "Only NGINX has a published host port",
        only_nginx_has_published_port()
        )
    
    if failures:
            print(f"\nValidation failed: {failures} check(s) failed.")
            return 1
    
    print("\nValidation passed.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
