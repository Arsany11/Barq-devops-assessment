# Redis storage implementation and its limits

**Implementation:** Redis runs with `--appendonly yes` (AOF). Its `/data` directory is a PersistentVolumeClaim (`redis-data`, 1Gi, ReadWriteOnce) on the `ebs-sc` StorageClass, which uses the AWS EBS CSI driver and gp3 volumes. The Deployment uses the `Recreate` strategy so two pods never fight for the same volume.

**What survives**
- Deleting or crashing the Redis pod: yes, shown by the counter continuing after the pod was recreated.
- Rescheduling Redis to the other node: yes, if that node is in the same availability zone. EBS volumes are detached and attached by the CSI driver.
- Replacing a worker node: the data survives, because it lives on the EBS volume and not on the node. Redis starts again on any node in the same AZ.

**Limits**
- An EBS volume exists in a single availability zone. If that AZ fails, Redis cannot start elsewhere until the volume is restored from a snapshot. Both nodes sit in one AZ in this design.
- If a node dies abruptly, AWS may take a few minutes to release the volume before it can attach to another node.
- One Redis replica means no high availability: Redis is unavailable while the pod restarts.
- The StorageClass reclaim policy is `Delete`, so deleting the PVC deletes the volume and its data.
- No automatic backups. EBS snapshots would be needed for that.
- The local rehearsal used `local-path` storage, which keeps data on one node's disk and does **not** survive worker replacement. It was only for practice.
