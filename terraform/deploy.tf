resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "django_secret_cosmetic" {
  length  = 48
  special = false
}

resource "random_password" "django_secret_codehelp" {
  length  = 48
  special = false
}

locals {
  deploy_enabled = trimspace(var.deploy_git_repo) != ""

  env_postgres_generated = <<-EOT
POSTGRES_USER=app
POSTGRES_PASSWORD=${random_password.postgres.result}
POSTGRES_DB=app
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
EOT

  env_cosmetic_postgres_effective = trimspace(var.env_cosmetic_postgres) != "" ? var.env_cosmetic_postgres : local.env_postgres_generated
  env_codehelp_postgres_effective = trimspace(var.env_codehelp_postgres) != "" ? var.env_codehelp_postgres : local.env_postgres_generated

  env_cosmetic_django_generated = join("\n", [
    "DJANGO_SETTINGS_MODULE=config.settings.production",
    "DJANGO_SECRET_KEY=${random_password.django_secret_cosmetic.result}",
    "DJANGO_DEBUG=False",
    "DJANGO_ALLOWED_HOSTS=*",
    "REDIS_URL=redis://redis:6379/0",
    "POSTGRES_HOST=postgres",
    "POSTGRES_PORT=5432",
    "POSTGRES_DB=app",
    "POSTGRES_USER=app",
    "POSTGRES_PASSWORD=${random_password.postgres.result}",
  ])

  env_codehelp_django_generated = join("\n", [
    "DJANGO_SETTINGS_MODULE=config.settings.production",
    "DJANGO_SECRET_KEY=${random_password.django_secret_codehelp.result}",
    "DJANGO_DEBUG=False",
    "DJANGO_ALLOWED_HOSTS=*",
    "REDIS_URL=redis://redis:6379/1",
    "POSTGRES_HOST=postgres",
    "POSTGRES_PORT=5432",
    "POSTGRES_DB=app",
    "POSTGRES_USER=app",
    "POSTGRES_PASSWORD=${random_password.postgres.result}",
  ])

  env_cosmetic_django_effective = trimspace(var.env_cosmetic_django) != "" ? var.env_cosmetic_django : local.env_cosmetic_django_generated
  env_codehelp_django_effective = trimspace(var.env_codehelp_django) != "" ? var.env_codehelp_django : local.env_codehelp_django_generated
}
