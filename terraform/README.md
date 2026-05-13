# Terraform: EC2 for Docker Compose stack

This module creates a single Ubuntu 22.04 EC2 instance (default `t3.micro`, Free Tier), a security group (SSH 22, HTTP 80, HTTPS 443, 3000, 4000), an Elastic IP by default, installs Docker via `user_data`, creates the Docker network `production_default`, and (when `deploy_git_repo` is set) brings the full `production.yml` stack up unattended.

To make the stack actually start on a 1 GiB Free Tier instance, `user_data` also:

1. Creates a swap file (`swap_size_gb`, default 6 GB on `/swapfile`).
2. Builds the local-only images that `production.yml` references but no registry has: `cosmetic_production_postgres`, `cosmetic_production_awscli`, `cosmetic_local_nginx`, `production_traefik:1.1` (uses `production-build.yml`).
3. Re-tags `djangoreactdev/cosmetic-api:1.0.2` as `cosmeticpro_production_celeryworker`/`celerybeat`/`flower` so the Celery services (whose image tags are not built anywhere) can start.
4. Generates `compose.override.yml` next to `production.yml` with `restart: unless-stopped` and per-service `mem_limit`s so the kernel swaps instead of OOM-killing.
5. Brings the stack up in waves: `postgres` + `redis` first, then the two API stacks, then the rest.

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.3.0`
- AWS credentials (for example `aws configure`, or environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`)

## Quick start

From this directory:

```powershell
cd C:\shere-folder\swarm-traefik-production\terraform
Copy-Item env.example terraform.tfvars   # one-time
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` is auto-loaded by Terraform, so no `-var` flags are needed. The shipped `env.example` is already filled with working values for this repo (`deploy_git_repo`, `deploy_git_branch=master`, `swap_size_gb=6`, etc.) - copying it as-is is enough for a first apply. Edit `terraform.tfvars` to override any value, including the four `env_*` blocks for real production secrets. The file is gitignored.

- **`terraform plan`** should not ask for `ssh_public_key` if you use the default (empty string): a key pair is generated automatically.
- After **`terraform apply`**, if the key was auto-generated, the private key is written to **`ec2_auto_key.pem`** in this same directory (ignored by Git). Permission is set to `0600` where the provider supports it. On **Windows**, OpenSSH still rejects the key if inherited ACLs allow `BUILTIN\Users` (or other principals) to read the file; run the **icacls** commands below once after each apply that recreates the key.

### Windows: fix `UNPROTECTED PRIVATE KEY FILE` / `Bad permissions`

From PowerShell (replace the path if you changed `ssh_generated_private_key_filename`):

```powershell
$key = "C:\shere-folder\swarm-traefik-production\terraform\ec2_auto_key.pem"
icacls $key /inheritance:r
icacls $key /grant:r "$($env:USERNAME):R"
```

Then retry SSH or Cursor Remote-SSH. Only your user account should remain on the ACL (read).

### Connect (user `ubuntu` on the Ubuntu AMI)

```powershell
terraform output ssh_command
```

Copy the printed line as-is. The suggested command uses **forward slashes** in the key path so it works in **PowerShell** without broken `\"` sequences. If you prefer quoting: `ssh -i 'C:\...\terraform\ec2_auto_key.pem' ubuntu@<IP>`.

Or manually, using the path from `terraform output ssh_private_key_file` and IP from `terraform output public_ip`.

Wait one to two minutes after the instance is ready for `user_data` (Docker and `production_default` network) to finish.

## Automated deploy (git clone + env files + compose)

When **`deploy_git_repo`** is non-empty, first boot also:

1. Installs **git**.
2. **`rm -rf` then `git clone`** into **`deploy_app_dir`** (default `/opt/swarm-app`) on the branch **`deploy_git_branch`**.
3. Writes the same four files as Jenkins `script.groovy`:  
   `cosmetic/.envs/.production/.django`, `cosmetic/.envs/.production/.postgres`,  
   `codehelp/.envs/.production/.django`, `codehelp/.envs/.production/.postgres`.
4. Runs **`docker compose -f deploy_compose_file pull`** then **`up -d`** in the clone directory.

If you do **not** set **`env_cosmetic_django`**, **`env_cosmetic_postgres`**, **`env_codehelp_django`**, **`env_codehelp_postgres`**, Terraform generates **minimal placeholders** (`random_password` for DB and Django secrets, single shared DB `app`). That is only a bootstrap; for production, pass real multiline contents via those variables (same idea as Jenkins credentials files).

**Security:** full env text is embedded in EC2 **user data** (base64). Anyone with EC2 describe permissions can read it. Prefer real secrets via a vault/SSM and a small bootstrap script if that is unacceptable.

**Logs on the instance:** `/var/log/cloud-init-output.log` for the full `user_data` log (swap, Docker install, build, pull, `compose up`). After SSH you can also run `docker compose -f production.yml -f compose.override.yml ps` and `docker compose ... logs <service>` from `deploy_app_dir`.

**Performance:** the full stack on `t3.micro` (1 vCPU, 1 GiB RAM + swap) is intentionally cramped — first boot can take 10–20 minutes for the build/pull step, and per-request latency will be high because Django/Node will partly run from swap on EBS. This is the trade-off for staying inside the Free Tier; bump `instance_type` to `t3.small`/`t3.medium` for real load.

## Optional variables

All inputs can be set in `terraform.tfvars` (see `env.example`). The most useful ones:

- **`ssh_public_key`**: if set to a non-empty OpenSSH public key line, Terraform uses it for `aws_key_pair` and does **not** create `ec2_auto_key.pem`. Use the matching private key on your machine for SSH.
- **`ssh_generated_private_key_filename`**: if you change the default `ec2_auto_key.pem`, add the new filename to `.gitignore` so the private key is never committed.
- **`swap_size_gb`**: size of the `/swapfile` created on first boot. Default `6` (GB). Set `0` to disable; the stack will then OOM on `t3.micro`.

See `variables.tf` for all inputs.

## If `terraform plan` still asks for `ssh_public_key`

That means `variables.tf` on disk still has a required `ssh_public_key` without `default`. Update this repository (or save `variables.tf`) so line `ssh_public_key` includes `default = ""`, then run `terraform init` again.

## State and secrets

Auto-generated keys exist in **Terraform state** and on disk in `ec2_auto_key.pem`. Keep `terraform.tfstate` and the key file private. Do not commit them (`.gitignore` already excludes state and `*.tfvars`).

## Destroy

```powershell
terraform destroy
```

This removes the instance and, when applicable, the generated key file managed by Terraform.
