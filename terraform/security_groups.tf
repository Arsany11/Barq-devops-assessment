resource "aws_security_group" "nodes" {
  name        = "${var.project}-nodes"
  description = "Kubernetes nodes"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-nodes-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds"
  description = "PostgreSQL from application nodes only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-rds-sg" }
}

locals {
  # Traffic allowed only between members of the nodes security group
  node_self_rules = {
    k8s_api        = { proto = "tcp", from = 6443, to = 6443 }
    kubelet        = { proto = "tcp", from = 10250, to = 10250 }
    etcd           = { proto = "tcp", from = 2379, to = 2380 }
    flannel_vxlan  = { proto = "udp", from = 8472, to = 8472 }
    nodeport_range = { proto = "tcp", from = 30000, to = 32767 }
  }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  for_each                     = local.node_self_rules
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = each.value.proto
  from_port                    = each.value.from
  to_port                      = each.value.to
  description                  = each.key
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "SSH from approved IP"
}

resource "aws_vpc_security_group_ingress_rule" "app_entry" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = var.allowed_app_cidr
  ip_protocol       = "tcp"
  from_port         = 30080
  to_port           = 30080
  description       = "Application entry point NodePort"
}

resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound for package installs and image pulls"
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from application nodes only"
}
