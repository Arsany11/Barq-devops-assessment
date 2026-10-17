[control]
control-plane ansible_host=${control_public} private_ip=${control_private}

[workers]
worker-1 ansible_host=${worker_public} private_ip=${worker_private}

[k8s:children]
control
workers

[k8s:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/barq-key
ansible_python_interpreter=/usr/bin/python3
