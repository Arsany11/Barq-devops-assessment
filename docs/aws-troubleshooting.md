# Troubleshooting notes (AWS Kubernetes project)

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | NGINX could not reach Flask | Two Service files defined `barq-app-service`; one had `targetPort: 80`, but Flask listens on 8080 | Kept one file with `targetPort: 8080`; checked with `kubectl get endpoints` |
| 2 | Cross-node timeouts, DNS failing, worker `NotReady` | Rocky `firewalld` blocked Flannel (UDP 8472) and the pod network; VM had been powered off | Opened UDP 8472, 10250/tcp, the NodePort range; trusted 10.244.0.0/16; restarted the node |
| 3 | `/ready` OK but `/records` returned `postgres_unavailable` | The `records` table did not exist; `init.sql` only runs on a fresh data directory, and never on RDS | Added a `db-init` Job that creates the table if it is missing |
| 4 | One `redis_unavailable` right after recreating the Redis pod | Service endpoints were switching to the new pod | Waited a few seconds after the pod was Ready; counter then continued from the saved value |
| 5 | Postgres pod in CrashLoopBackOff with `exec format error` | Damaged image copy on one node after an unclean VM shutdown | Removed the image with `crictl rmi`, let the node pull it again |
| 6 | `docker push` timed out | Slow connection to Docker Hub | Re-ran the push; finished layers are kept |
| 7 | Rollout to `v2` still showed version 2.0.0 | Image was built before the file edit was saved; tags are cached with `IfNotPresent` | Verified the version inside the image with `docker run` before pushing; pushed a new tag `2.1.0` |
| 8 | `aws ec2 ...` said "You must specify a region" | `aws configure` was left without a default region | `aws configure set region eu-central-1` |
| 9 | `terraform apply` failed with "account is currently blocked" on `RunInstances` | AWS account verification (not a code problem) | Opened an AWS support case; resolution: _fill in when resolved_ |
