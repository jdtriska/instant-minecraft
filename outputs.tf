output "minecraft_host" {
  value = local.server_name
}

output "minecraft_server_ssh_command" {
  value = "ssh -i \"./.ssh/minecraft-key\" ec2-user@${aws_eip.minecraft_eip.public_ip}"
}

output "minecraft_backup_bucket" {
  value = aws_s3_bucket.backup.arn
}