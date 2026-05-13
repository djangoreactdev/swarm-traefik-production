output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Public IP to SSH (ubuntu user) and for Traefik 80/443."
  value       = var.associate_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
}

output "ssh_private_key_file" {
  description = "Absolute path to the auto-generated private key file; null if ssh_public_key was set (use your own key file)."
  value       = length(local_file.generated_ssh_private_key) > 0 ? local_file.generated_ssh_private_key[0].filename : null
}

output "ssh_command" {
  description = "Example SSH for user ubuntu. Path uses forward slashes (no extra quotes) so copy-paste works in PowerShell and bash."
  value = format(
    "ssh -i %s ubuntu@%s",
    length(local_file.generated_ssh_private_key) > 0 ? replace(local_file.generated_ssh_private_key[0].filename, "\\", "/") : "<path-to-your-private-key>",
    var.associate_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
  )
}

output "compose_network_hint" {
  description = "production.yml external network production_default is created on first boot (user_data); re-run create only if you removed it."
  value       = "docker network inspect production_default >/dev/null 2>&1 || docker network create production_default"
}
