resource "aws_instance" "app" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    Name        = "bacasable"
    Environment = "production"
  }
}

resource "aws_security_group" "app" {
  name        = "bacasable-sg"
  description = "Security group for bacasable"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
