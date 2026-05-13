resource "tls_private_key" "generated" {
  count     = trimspace(var.ssh_public_key) == "" ? 1 : 0
  algorithm = "ED25519"
}

resource "local_file" "generated_ssh_private_key" {
  count           = length(tls_private_key.generated)
  content         = tls_private_key.generated[0].private_key_openssh
  filename        = abspath("${path.module}/${var.ssh_generated_private_key_filename}")
  file_permission = "0600"
}

locals {
  ec2_public_key_openssh = trimspace(var.ssh_public_key) != "" ? trimspace(var.ssh_public_key) : tls_private_key.generated[0].public_key_openssh
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = local.ec2_public_key_openssh
}

resource "aws_security_group" "this" {
  name        = "${var.project_name}-sg"
  description = "Traefik + cosmetic-nginx + SSH"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    description = "HTTP (Traefik)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_https_cidr_blocks
  }

  ingress {
    description = "HTTPS (Traefik)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.http_https_cidr_blocks
  }

  ingress {
    description = "cosmetic-nginx"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.app_ports_cidr_blocks
  }

  ingress {
    description = "cosmetic-nginx"
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = var.app_ports_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.this.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
  }

  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    deploy_enabled        = local.deploy_enabled
    deploy_git_repo       = var.deploy_git_repo
    deploy_git_branch     = var.deploy_git_branch
    deploy_app_dir        = var.deploy_app_dir
    deploy_compose_file   = var.deploy_compose_file
    swap_size_gb          = var.swap_size_gb
    b64_cosmetic_postgres = base64encode(local.env_cosmetic_postgres_effective)
    b64_codehelp_postgres = base64encode(local.env_codehelp_postgres_effective)
    b64_cosmetic_django   = base64encode(local.env_cosmetic_django_effective)
    b64_codehelp_django   = base64encode(local.env_codehelp_django_effective)
  })

  tags = {
    Name = var.project_name
  }
}

resource "aws_eip" "this" {
  count    = var.associate_elastic_ip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.this.id

  tags = {
    Name = "${var.project_name}-eip"
  }
}
