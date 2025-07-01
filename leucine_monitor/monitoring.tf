provider "aws" {
  region = "ap-south-1"
}

variable "instance_type" {
  default = "t3.small"
}

variable "key_name" {
  description = "Name of your existing EC2 key pair"
}

variable "subnet_id" {
  description = "Subnet ID where EC2 should launch"
}

variable "security_group_id" {
  description = "Security Group ID to attach"
}

resource "aws_instance" "monitoring" {
  ami                         = "ami-0f5ee92e2d63afc18" # Ubuntu 22.04 in ap-south-1
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              echo "🔧 Updating packages..."
              apt-get update -y && apt-get upgrade -y

              echo "🐳 Installing Docker..."
              apt-get install -y docker.io docker-compose
              systemctl start docker
              systemctl enable docker

              echo "🐙 Installing Git..."
              apt-get install -y git

              echo "🛡️ Installing Caddy..."
              apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
              curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
              curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sed 's|signed-by=[^ ]*|signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg|' > /etc/apt/sources.list.d/caddy-stable.list
              apt update && apt install caddy -y

              echo "📦 Cloning monitoring repo..."
              cd /opt
              git clone https://github.com/PrashanthMJ21/monitoring.git
              cd monitoring/leucine_monitor

              echo "🚀 Running setup script..."
              chmod +x setup.sh
              ./setup.sh > /var/log/leucine_monitoring_setup.log 2>&1

              echo "✅ Done setting up Monitoring stack."
              EOF

  tags = {
    Name = "Leucine-Monitoring-Instance"
  }
}

output "monitoring_instance_ip" {
  value = aws_instance.monitoring.public_ip
  description = "Public IP of the Monitoring EC2 instance"
}
