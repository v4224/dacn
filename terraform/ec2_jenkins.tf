resource "aws_instance" "jenkins" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2
  instance_type = "t3.large"
  subnet_id     = module.vpc.public_subnets[0]
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              yum install -y java-1.8.0-openjdk git
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user

              # Jenkins
              wget -O /etc/yum.repos.d/jenkins.repo \
                https://pkg.jenkins.io/redhat-stable/jenkins.repo
              rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
              yum install -y jenkins
              systemctl enable jenkins
              systemctl start jenkins

              # Docker Compose + SonarQube
              curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose

              mkdir -p /opt/sonarqube
              cd /opt/sonarqube
              cat << EOT >> docker-compose.yml
              version: '3'
              services:
                sonarqube:
                  image: sonarqube:lts
                  ports:
                    - "9000:9000"
              EOT
              docker-compose up -d
              EOF

  tags = {
    Name = "jenkins-master"
  }
}

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Allow HTTP/SSH"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
