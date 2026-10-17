# Architecture (AWS)

```mermaid
flowchart LR
  user["Approved IP"] -->|"NodePort 30080"| nginx
  subgraph vpc["VPC 10.0.0.0/16"]
    subgraph pub["Public subnet 10.0.1.0/24: EC2 control-plane + EC2 worker"]
      subgraph k8s["Kubernetes cluster (kubeadm + Flannel)"]
        nginx["NGINX"]
        flask1["Flask replica 1"]
        flask2["Flask replica 2"]
        redis["Redis + EBS PVC"]
      end
    end
    subgraph priv["Private DB subnets in 2 AZs"]
      rds[("RDS PostgreSQL")]
    end
  end
  nginx --> flask1
  nginx --> flask2
  flask1 --> redis
  flask2 --> redis
  flask1 -->|"5432, nodes security group only"| rds
  flask2 -->|"5432, nodes security group only"| rds
```
Pod placement is decided by the Kubernetes scheduler, so the two Flask replicas normally land on different nodes.

**Access method:** the only exposed entry point is NodePort 30080 on the nodes, reachable only from the approved IP in the security group. SSH (22) is limited to the same IP.
