#!/usr/bin/env bash
# Run on the control-plane node.
# Usage: NODE_IP=<node public ip> RDS_ENDPOINT=<rds host> DB_PASS=<password> ./verify.sh | tee verification.txt
set -u
: "${NODE_IP:?set NODE_IP}" "${RDS_ENDPOINT:?set RDS_ENDPOINT}" "${DB_PASS:?set DB_PASS}"
U="http://${NODE_IP}:30080"
TS=$(date +%s)
hdr() { printf '\n\n=================== %s ===================\n' "$1"; }
get() { curl -s -m 10 -w '\n[HTTP %{http_code}]\n' "$U$1"; }
counter() { curl -s -m 10 "$U/counter" | grep -o '"counter":[0-9]*'; }

hdr "1. Endpoints"
for p in / /health /ready /instance /records /counter; do echo "--- GET $p"; get "$p"; done

hdr "2. RDS proof: write through the API, read back directly from RDS"
curl -s -m 10 -X POST "$U/records" -H 'Content-Type: application/json' -d "{\"title\":\"rds-proof-$TS\"}" -w '\n[HTTP %{http_code}]\n'
kubectl run psql-check --rm -i --restart=Never --image=postgres:16-alpine --env="PGPASSWORD=$DB_PASS" --command -- \
  psql -h "$RDS_ENDPOINT" -U barq_app -d barq_tasks -c "SELECT id, title FROM records ORDER BY id DESC LIMIT 5;"

hdr "3. Record survives Flask pod recreation"
curl -s -m 10 -X POST "$U/records" -H 'Content-Type: application/json' -d "{\"title\":\"persist-$TS\"}" -w '\n[HTTP %{http_code}]\n'
kubectl get pods -l app=barq-app
kubectl delete pod -l app=barq-app
sleep 8
kubectl wait --for=condition=Ready pod -l app=barq-app --timeout=180s
kubectl get pods -l app=barq-app -o wide
sleep 5
curl -s -m 10 "$U/records" | grep -o "persist-$TS" || echo "RECORD NOT FOUND"

hdr "4. Redis counter survives Redis pod recreation (PVC kept)"
kubectl get pvc redis-data
counter; counter
echo "value before deleting the Redis pod:"; counter
kubectl delete pod -l app=redis
sleep 8
kubectl wait --for=condition=Ready pod -l app=redis --timeout=180s
sleep 8
echo "value after (must continue, not restart at 1):"; counter
kubectl get pvc redis-data

hdr "5. Both Flask replicas answer through NGINX"
for i in $(seq 1 20); do curl -s -m 10 -D - -o /dev/null "$U/instance" | tr -d '\r' | grep -i '^x-instance-id'; done | sort | uniq -c

hdr "6. Self-healing: delete one Flask pod"
kubectl get pods -l app=barq-app
VICTIM=$(kubectl get pod -l app=barq-app -o name | head -1)
kubectl delete "$VICTIM" --wait=false
sleep 3
kubectl get pods -l app=barq-app
sleep 15
kubectl get pods -l app=barq-app -o wide

hdr "7. Service DNS and cross-node pod communication"
kubectl get pods -o wide
kubectl get svc
kubectl exec deploy/nginx-proxy -- sh -c 'nslookup barq-app-service; nslookup redis; wget -qO- -T 5 http://barq-app-service/health'
for ip in $(kubectl get pods -l app=barq-app -o jsonpath='{.items[*].status.podIP}'); do
  echo "NGINX pod -> Flask pod $ip:"; kubectl exec deploy/nginx-proxy -- wget -qO- -T 5 "http://$ip:8080/health"; echo
done

hdr "8. Update to 2.1.0, verify, roll back, verify"
echo "before:"; curl -s "$U/" | grep -o '"version":"[^"]*"'
kubectl set image deploy/barq-app app=arsany33/barq:2.1.0
kubectl rollout status deploy/barq-app --timeout=180s
echo "after update:"; curl -s "$U/" | grep -o '"version":"[^"]*"'
kubectl rollout undo deploy/barq-app
kubectl rollout status deploy/barq-app --timeout=180s
echo "after rollback:"; curl -s "$U/" | grep -o '"version":"[^"]*"'
kubectl rollout history deploy/barq-app

hdr "9. Redis storage details (for the storage limitation section)"
kubectl get pvc,pv
kubectl describe pv | grep -E "Name:|StorageClass:|Node Affinity|zone|VolumeHandle"
