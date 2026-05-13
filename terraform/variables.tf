variable "aws_region" {
  type        = string
  description = "AWS region for the instance (e.g. eu-central-1)."
  default     = "eu-central-1"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type. t3.micro or t2.micro are eligible for Free Tier (limits apply)."
  default     = "t3.micro"
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names."
  default     = "swarm-traefik-production"
}

variable "ssh_public_key" {
  type        = string
  description = "OpenSSH public key (one line from .pub). Leave empty to auto-generate a key pair; the private key is written to ssh_generated_private_key_filename (gitignored) and stored in Terraform state."
  default     = ""
  sensitive   = true
}

variable "ssh_generated_private_key_filename" {
  type        = string
  description = "When ssh_public_key is empty, the generated private key is written under this terraform directory (relative path, e.g. ec2_auto_key.pem)."
  default     = "ec2_auto_key.pem"
}

variable "ssh_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH (port 22). Prefer your public IP /32 instead of 0.0.0.0/0."
  default     = ["0.0.0.0/0"]
}

variable "http_https_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed for Traefik HTTP/HTTPS (80, 443)."
  default     = ["0.0.0.0/0"]
}

variable "app_ports_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed for cosmetic-nginx ports 3000 and 4000 from production.yml."
  default     = ["0.0.0.0/0"]
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root EBS volume size in GB (30 GB is within typical Free Tier EBS allowance for 12 months)."
  default     = 30
}

variable "swap_size_gb" {
  type        = number
  description = "Swap file size in GB created by user_data on first boot. Required on t3.micro (1 GiB RAM) so the full production.yml stack can start. Set 0 to disable."
  default     = 6
}

variable "associate_elastic_ip" {
  type        = bool
  description = "If true, allocate and attach an Elastic IP (same public IP after instance stop/start). Set false only if you accept a changing public IP."
  default     = true
}

variable "deploy_git_repo" {
  type        = string
  description = "Git repository URL to clone (HTTPS or SSH). When non-empty: clone into deploy_app_dir, write four production env files, then docker compose pull && up -d."
  default     = ""
  sensitive   = true
}

variable "deploy_git_branch" {
  type        = string
  description = "Git branch for deploy_git_repo clone."
  default     = "master"
}

variable "deploy_app_dir" {
  type        = string
  description = "Absolute path on the instance where the repository is cloned (removed and re-cloned on each user_data run)."
  default     = "/opt/swarm-app"
}

variable "deploy_compose_file" {
  type        = string
  description = "Compose file name inside the cloned repository."
  default     = "production.yml"
}

variable "env_cosmetic_django" {
  type        = string
  description = "Full contents for cosmetic/.envs/.production/.django. Empty uses an auto-generated minimal placeholder (not production-hardened)."
  default     = ""
  sensitive   = true
}

variable "env_cosmetic_postgres" {
  type        = string
  description = "Full contents for cosmetic/.envs/.production/.postgres. Empty uses an auto-generated placeholder matching codehelp postgres for a single shared DB user/db."
  default     = ""
  sensitive   = true
}

variable "env_codehelp_django" {
  type        = string
  description = "Full contents for codehelp/.envs/.production/.django. Empty uses an auto-generated minimal placeholder."
  default     = ""
  sensitive   = true
}

variable "env_codehelp_postgres" {
  type        = string
  description = "Full contents for codehelp/.envs/.production/.postgres. Empty uses the same auto-generated postgres block as cosmetic when both are empty."
  default     = ""
  sensitive   = true
}
