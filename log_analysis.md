# Log analysis

Incident window: **2026-08-20, 11:00–11:30 UTC**. Files: `access.log` (nginx, JSON),
`application.log` (app tier, JSON), `error.log` (nginx text). Reproduce everything with
`python3 analyze.py .` (script attached).

## Commands / scripts

Key parsing logic (full script in `analyze.py`):

```python
# JSON logs: count malformed lines and exact duplicate lines
for raw in f:
    line = raw.strip()
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        malformed += 1
        continue
    seen[line] += 1  # duplicate if seen[line] > 1

# error.log line format:
# 2026/08/20 11:05:02 [error] ... request_id=lab-000122, request: "GET /health HTTP/1.1", upstream: "http://172.23.0.12:8080/health"
re.match(r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(\w+)\] .*", line)
```

## Results

**1. UTC interval; valid / malformed / duplicate lines**

| file | lines | valid | malformed | duplicates |
|---|---|---|---|---|
| access.log | 726 | 725 | 1 (truncated JSON) | 5 |
| application.log | 730 | 729 | 1 (truncated JSON) | 2 |
| error.log | 68 | 68 | 0 | 0 |

Window: 11:00:00 → 11:30:00 UTC. Duplicates are byte-identical repeated lines (log-shipper resend
artifact) — dropped, keeping the first copy.

**2. Distinct client requests: 720**

After removing malformed/duplicate lines, `access.log` has 720 unique `request_id`s
(`lab-000001`–`lab-000720`, no gaps). Retries aren't double-counted because nginx logs a retried
request as **one line**, with comma-separated `upstream`/`upstream_status`
(e.g. `"172.23.0.12:8080, 172.23.0.11:8080"`, `"502, 200"`) — so counting distinct `request_id`s
already counts each client request once.

**3. Final status counts & error rate**

`{200: 615, 404: 10, 502: 40, 503: 47, 504: 8}` — denominator = 720 distinct requests.
**5xx error rate = 95/720 = 13.2%**.

**4. Failures by path / window / backend**

| window | status | path(s) | backend(s) |
|---|---|---|---|
| 11:05–11:09 | 502 (40) | mixed (`/health`,`/`,`/counter`,`/records`) | only `172.23.0.12` |
| 11:12–11:15 | 503 (31) | `/ready`, `/counter` | both instances |
| 11:20–11:21 | 503 (16) | `/ready`, `/records` | both instances |
| 11:25–11:26 | 504 (8) | `/records` only | both instances |

**5. Median and p95 latency** (access.log `request_time`, seconds → ms, n=720)

- Method: linear-interpolation percentile.
- Median: **54 ms**
- p95: **2001 ms** — dragged up by the dependency-timeout-bound 503s (~2000–2500 ms each)

**6. Retries**

19 requests were retried to a second upstream (all 11:05–11:09, first attempt refused by `.12`,
retried to `.11`). **All 19 succeeded.** Separately, 40 more refused-connection attempts had no
retry and returned 502 straight to the client.

**9. Proxy vs. app/dependency errors**

- **Proxy/connectivity** (11:05–11:09 refusals, 11:25 `/records` timeouts): visible in
  `error.log` as nginx-level connect/timeout failures. Proof: the 40 non-retried refusals have
  **no matching `application.log` entry** — the app was never reached.
- **App/dependency** (11:12–11:15 redis, 11:20–11:21 postgres): never appear in `error.log` —
  nginx got a normal response, it just happened to be 503. Proof: `application.log` shows an
  `ERROR`-level `dependency_error` (redis `TimeoutError` / postgres `InvalidPassword`) paired with
  a `WARN` `http_request` 503, same `request_id`, on both app instances.

## Timeline and correlated examples

**7. Incident timeline**

| time (UTC) | source | what happened |
|---|---|---|
| 11:05:02–11:09:57 | error + access | `172.23.0.12` refusing connections (TCP `Connection refused`). 19 requests retried to `.11` and succeeded; 40 got no retry → 502. |
| 11:12:09–11:15:52 | application | Redis timeouts on both app instances → 31× 503 on `/ready`, `/counter`. |
| 11:20:07–11:21:45 | application | Postgres `InvalidPassword` on both instances → 16× 503 on `/ready`, `/records`. |
| 11:25:14–11:26:47 | error + access | `/records` times out against **both** backends → 8× 504, no retries. |
| 11:29:57 | access | Traffic back to normal (200s). |

**8. Correlated examples**

Failed request (`lab-000122`, no retry, final 502):
```
error.log      : connect() failed (Connection refused), upstream 172.23.0.12:8080/health
access.log     : status 502, upstream "172.23.0.12:8080", request_time 0.003
application.log: no record — request never reached the app tier
```

Successful request after retry (`lab-000124`):
```
error.log      : connect() failed (Connection refused) to 172.23.0.12:8080/ready
access.log     : upstream "172.23.0.12:8080, 172.23.0.11:8080", upstream_status "502, 200", final 200
application.log: served by app-01, status 200, duration_ms 120
```

## Conclusions and limits

**10. What the logs don't prove; what to check next**

- *Why* `.12` refused connections (crash, restart, firewall change?) — no host/process logs here.
- Whether the Postgres `InvalidPassword` was a credential rotation, bad deploy, or something else.
- Why `/records` hung long enough to time out both instances at 11:25 — no app-log entries in
  that window to explain it.
- All traffic here is from one client IP, may not reflect real production traffic mix.

Next steps in a running environment:
- Check host/orchestrator events for `.12` around 11:05–11:09.
- Check Redis and Postgres server-side logs/metrics for their respective windows (especially
  Postgres auth logs for the `InvalidPassword` errors).
- Check whatever `/records` calls downstream, to explain the 11:25 timeouts.
- Check alerting/paging history to see how quickly these windows were detected in practice.