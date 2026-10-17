variable "region" {
  default = "eu-central-1"
}

variable "project" {
  default = "barq"
}

variable "owner" {
  type = string
}

variable "env" {
  default = "dev"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "db_subnet_cidrs" {
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "Your public IP as x.x.x.x/32, the only source allowed to SSH"
}

variable "allowed_app_cidr" {
  type        = string
  description = "Who may reach the NodePort 30080"
}

variable "instance_type" {
  default = "t3.small"
}

variable "public_key_path" {
  default = "~/.ssh/barq-key.pub"
}

variable "db_name" {
  default = "barq_tasks"
}

variable "db_username" {
  default = "barq_app"
}

variable "db_instance_class" {
  default = "db.t3.micro"
}

variable "db_password" {
  type      = string
  sensitive = true
}
