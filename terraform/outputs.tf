output "control_plane_public_ip" {
  value = aws_instance.node["control-plane"].public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.node["control-plane"].private_ip
}

output "control_plane_instance_id" {
  value = aws_instance.node["control-plane"].id
}

output "worker_public_ip" {
  value = aws_instance.node["worker"].public_ip
}

output "worker_private_ip" {
  value = aws_instance.node["worker"].private_ip
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

# Generates the Ansible inventory from the real addresses
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content = templatefile("${path.module}/inventory.tpl", {
    control_public  = aws_instance.node["control-plane"].public_ip
    control_private = aws_instance.node["control-plane"].private_ip
    worker_public   = aws_instance.node["worker"].public_ip
    worker_private  = aws_instance.node["worker"].private_ip
  })
}
