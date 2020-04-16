/**
 * This is our terraform config.
 * We use partial configuration here (see https://www.terraform.io/docs/backends/config.html).
 * This lets us provide the rest of the config variables via docker-compose
 *   from a .env file rather than hard coding them here.
 */
terraform {
  backend "s3" {}
  required_providers {
    aws = "~>2.53"
  }
}

locals {
  server_name = var.HOSTED_ZONE_ID == "" ? aws_eip.minecraft_eip.public_ip : trimsuffix(data.aws_route53_zone.minecraft_domain.0.name,".")
}
/**
 * This is our provider setup.
 * Feel free to try out other cloud providers using this as a template.
 */

data "aws_route53_zone" "minecraft_domain" {
  count = var.HOSTED_ZONE_ID == "" ? 0 : 1
  zone_id = var.HOSTED_ZONE_ID
}

provider "aws" {
  region = var.AWS_REGION
  access_key = var.AWS_ACCESS_KEY_ID
  secret_key = var.AWS_SECRET_ACCESS_KEY
}


resource "aws_s3_bucket" "backup" {
  bucket = "${var.ENVIRONMENT}-minecraft-backup"
  lifecycle_rule {
    id      = "backups"
    enabled = true
    expiration {
      days = 7
    }
  }
  tags = {
    Name        = "${var.ENVIRONMENT}-minecraft-backup"
    Environment = var.ENVIRONMENT
  }
}

/**
 * This sets up the permissions our EC2 instance will need to sync
 *   with S3.
 */

resource "aws_iam_role" "minecraft_server_role" {
  name = "${var.ENVIRONMENT}-minecraft-server-role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
  tags = {
    Name        = "${var.ENVIRONMENT}-minecraft-server-role"
    Environment = var.ENVIRONMENT
  }
}

resource "aws_iam_role_policy" "minecraft_server_policy" {
  name = "${var.ENVIRONMENT}-minecraft-server-policy"
  role = aws_iam_role.minecraft_server_role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "Backups",
        "Action": [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_s3_bucket.backup.arn}",
          "${aws_s3_bucket.backup.arn}/*"
        ]
      }
    ]
  }
  EOF
}

resource "aws_iam_instance_profile" "minecraft_instance_profile" {
  name = "${var.ENVIRONMENT}-minecraft-instance-profile"
  role = aws_iam_role.minecraft_server_role.name
}

/**
 * We get the latest amazon linux 2 ami...
 */

data "aws_ami" "amazon_linux_2" {
 most_recent = true
  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

/**
 * This is our actual Minecraft server.
 * The instance and storage size are configurable so you can tune the performance and
 *   cost exactly how you want.
 * The provisioner blocks are there to:
 *   1. Copy our setup scripts to the server
 *   2. Run the setup scripts and start the Minecraft server
 * If you need to remotely administer your server, please see the AWS docs for
 *   how to connect via SSH (I've left those ports open to the internet).
 */

resource "aws_security_group" "minecraft_server_sg" {
  name = "${var.ENVIRONMENT}-minecraft-server-sg"
  description = "Security group which allows SSH from anywhere and HTTP/S access from the load balancer"
  vpc_id = aws_vpc.minecraft_vpc.id
  ingress {
    description = "TCP client connections from anywhere"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "UDP client connections from anywhere"
    from_port   = 25565
    to_port     = 25565
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.ENVIRONMENT}-minecraft-server-sg"
    Environment = var.ENVIRONMENT
  }
}

resource "aws_key_pair" "minecraft_keys" {
  key_name   = "minecraft-key"
  public_key = file(".ssh/minecraft-key.pub")
}

resource "aws_eip" "minecraft_eip" {
  instance = aws_instance.minecraft_server.id
  tags = {
    Name        = "${var.ENVIRONMENT}-minecraft-eip"
    Environment = var.ENVIRONMENT
  }
  vpc = true
}

resource "aws_instance" "minecraft_server" {
  key_name = aws_key_pair.minecraft_keys.key_name
  ami = data.aws_ami.amazon_linux_2.id
  instance_type = var.EC2_INSTANCE_TYPE
  iam_instance_profile = aws_iam_instance_profile.minecraft_instance_profile.name
  associate_public_ip_address = true
  root_block_device {
    volume_size = var.EBS_ROOT_VOLUME_SIZE
  }
  vpc_security_group_ids = [aws_security_group.minecraft_server_sg.id]
  subnet_id = aws_subnet.minecraft_public.id
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file(".ssh/minecraft-key")
    host     = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir ~/minecraft",
      "mkdir ~/minecraft/scripts",
      "mkdir ~/minecraft/data",
      "sudo yum install -y docker dos2unix",
      "sudo usermod -a -G docker ec2-user",
      "sudo systemctl enable docker"
    ]
  }

  // Lays down docker script
  provisioner "file" {
    content = file("files/start-minecraft.sh")
    destination = "/tmp/start-minecraft.sh"
  }

  // Starts Minecraft backups to S3
  provisioner "file" {
    content = file("files/start-backup.sh")
    destination = "/tmp/start-backup.sh"
  }


  // Creates backup script for Minecraft data
  provisioner "file" {
    content = templatefile("templates/backup.sh.tmpl", { BUCKET = aws_s3_bucket.backup.id })
    destination = "/tmp/backup.sh"
  }

  // Creates restore script for Minecraft data
  provisioner "file" {
    content = templatefile("templates/restore.sh.tmpl", { BUCKET = aws_s3_bucket.backup.id })
    destination = "/tmp/restore.sh"
  }


   provisioner "remote-exec" {
    inline = [
      "mv /tmp/start-minecraft.sh ~/minecraft/scripts/start-minecraft.sh",
      "mv /tmp/start-backup.sh ~/minecraft/scripts/start-backup.sh",
      "mv /tmp/backup.sh ~/minecraft/scripts/backup.sh",
      "mv /tmp/restore.sh ~/minecraft/scripts/restore.sh",
      "dos2unix ~/minecraft/scripts/start-minecraft.sh",
      "dos2unix ~/minecraft/scripts/start-backup.sh",
      "dos2unix ~/minecraft/scripts/backup.sh",
      "dos2unix ~/minecraft/scripts/restore.sh",
      "/bin/bash ~/minecraft/scripts/start-minecraft.sh",
      "/bin/bash ~/minecraft/scripts/start-backup.sh"
    ]
  } 
  tags = {
    Name        = "${var.ENVIRONMENT}-minecraft-server"
    Environment = var.ENVIRONMENT
  }
}

/**
 * Next we'll create an SSL certificate for our domain, and the
 *   load balancer which will serve the certificate and route
 *   traffic to our EC2 instance.
 * There is a lot of networking below, as well as optional resources for
 *   if you've provided a domain.
 */

resource "aws_vpc" "minecraft_vpc" { 
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "${var.ENVIRONMENT}-minecraft-vpc"
    Environment = var.ENVIRONMENT
  }
}

resource "aws_internet_gateway" "minecraft_igw" {
  vpc_id = aws_vpc.minecraft_vpc.id
  tags = {
    Name = "${var.ENVIRONMENT}-minecraft_igw"
    Environment = var.ENVIRONMENT
  }
}

resource "aws_default_route_table" "minecraft_route" {
  default_route_table_id = aws_vpc.minecraft_vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minecraft_igw.id
  }
  tags = {
    Name = "${var.ENVIRONMENT}-minecraft-route"
    Environment = var.ENVIRONMENT
  }
}

resource "aws_subnet" "minecraft_public" {
  vpc_id     = aws_vpc.minecraft_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "${var.AWS_REGION}a"
  tags = {
    Name = "${var.ENVIRONMENT}-minecraft_public"
    Environment = var.ENVIRONMENT
  }
}

/**
 * Finally, with the networking set up, we can put our domain in front of our load balancer.
 * We only do this if you provided a domain.
 */

resource "aws_route53_record" "minecraft_domain_record" {
  count = var.HOSTED_ZONE_ID == "" ? 0 : 1
  zone_id = data.aws_route53_zone.minecraft_domain.0.zone_id
  name    = trimsuffix(data.aws_route53_zone.minecraft_domain.0.name,".")
  type    = "A"
  ttl     = 3600
  records = [aws_eip.minecraft_eip.public_ip]
}