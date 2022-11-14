terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.18.0"
    }
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = ""
  secret_key = ""
}
/////////////////////////////VPC ////////////////////////////////
resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { "Name" = "app-vpc" }
}

/////////////////////////Subnets////////////////////////////////

/////////////////////////frontend-subnets//////////////////////////////
resource "aws_subnet" "subnet-pub-region-a" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet Region A"
  }
}

resource "aws_subnet" "subnet-pub-region-b" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet Region B"
  }
}

//////////////////////////////Backend-subnets///////////////////////////
resource "aws_subnet" "subnet-pri-region-a" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "Private Subnet Region A"
  }
}

resource "aws_subnet" "subnet-pri-region-b" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.12.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "Private Subnet Region B"
  }
}

///////////////////Database Subnets///////////////////////////////
resource "aws_subnet" "database-subnet-region-a" {
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Region A Database Subnet"
  }
}

resource "aws_subnet" "database-subnet-region-b" {
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Region B Database Subnet"
  }
}


//////////////////////////////Internet Gateway////////////////////////
resource "aws_internet_gateway" "internet-gateway" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    "Name" = "Internet Gateway"
  }
}
////////////////////Route Table///////////////////////////


///////////////////////////Public Route//////////////////////////
resource "aws_route_table" "public-route" {
  vpc_id = aws_vpc.dev_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway.id
  }
}

resource "aws_route_table_association" "public_route_association-region-a" {
  subnet_id      = aws_subnet.subnet-pub-region-a.id
  route_table_id = aws_route_table.public-route.id
}

resource "aws_route_table_association" "public_route_association-region-b" {
  subnet_id      = aws_subnet.subnet-pub-region-b.id
  route_table_id = aws_route_table.public-route.id
}

resource "aws_security_group" "public-sg" {
  name   = "public-sg"
  vpc_id = aws_vpc.dev_vpc.id

  ingress {
    description = "Public"
    from_port   = 80
    to_port     = 80
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
resource "aws_security_group" "private-sg" {
  name   = "private-sg"
  vpc_id = aws_vpc.dev_vpc.id

  ingress {
    description     = "Private"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.public-sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "database-sg" {
  name   = "Database-Sg"
  vpc_id = aws_vpc.dev_vpc.id
  ingress {
    description     = "Database Sg"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.private-sg.id]
  }
  egress {
    from_port   = 32768
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

///////////////////// Frontend Service Setup/////////////

resource "aws_launch_configuration" "frontend-lc" {
  name_prefix                 = "frontend-asg-"
  image_id                    = "ami-052efd3df9dad4825"
  instance_type               = "t2.micro"
  security_groups             = [aws_security_group.public-sg.id]
  user_data                   = file("web.sh")
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "frontend-asg" {
  min_size             = 2
  max_size             = 4
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.frontend-lc.name
  vpc_zone_identifier  = [aws_subnet.subnet-pub-region-a.id, aws_subnet.subnet-pub-region-b.id]

  depends_on = [
    aws_launch_configuration.frontend-lc
  ]
}

resource "aws_lb" "public-elb" {
  name               = "Public-LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public-sg.id]
  subnets            = [aws_subnet.subnet-pub-region-a.id, aws_subnet.subnet-pub-region-b.id]
}

resource "aws_lb_target_group" "public-elb" {
  name     = "ALB-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dev_vpc.id
}

resource "aws_autoscaling_attachment" "public-alb" {
  autoscaling_group_name = aws_autoscaling_group.frontend-asg.id
  lb_target_group_arn    = aws_lb_target_group.public-elb.arn
}

resource "aws_lb_listener" "public-alb" {
  load_balancer_arn = aws_lb.public-elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public-elb.arn
  }
}

////////////////////Backend Service Setup//////////////////

resource "aws_launch_configuration" "backend-lc" {
  name_prefix     = "backend-asg-"
  image_id        = "ami-052efd3df9dad4825"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.private-sg.id]
  user_data       = file("web.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "backend-asg" {
  min_size             = 2
  max_size             = 4
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.backend-lc.name
  vpc_zone_identifier  = [aws_subnet.subnet-pri-region-a.id, aws_subnet.subnet-pri-region-b.id]

  depends_on = [
    aws_launch_configuration.backend-lc
  ]
}

resource "aws_lb" "private-elb" {
  name               = "Private-LB"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.private-sg.id]
  subnets            = [aws_subnet.subnet-pri-region-a.id, aws_subnet.subnet-pri-region-b.id]
}

resource "aws_lb_target_group" "private-elb" {
  name     = "ALB-TG-PR"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dev_vpc.id
}

resource "aws_autoscaling_attachment" "private-alb" {
  autoscaling_group_name = aws_autoscaling_group.backend-asg.id
  lb_target_group_arn    = aws_lb_target_group.private-elb.arn
}

resource "aws_lb_listener" "private-alb" {
  load_balancer_arn = aws_lb.private-elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.private-elb.arn
  }
}

////////////////////////Database Creation/////////////////////////////////////

resource "aws_db_instance" "database" {
  allocated_storage      = 10
  db_subnet_group_name   = aws_db_subnet_group.database-subnet.id
  engine                 = "mysql"
  engine_version         = "8.0.20"
  instance_class         = "db.t2.micro"
  multi_az               = true
  db_name                = "mydb"
  username               = "test"
  password               = "password123"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.database-sg.id]
}

resource "aws_db_subnet_group" "database-subnet" {
  name       = "main"
  subnet_ids = [aws_subnet.database-subnet-region-a.id, aws_subnet.database-subnet-region-b.id]

  tags = {
    Name = "Database Subnets"
  }
}

/////////////////////Outputs////////////////////////////

output "All-Endpoints" {
  description = "The DNS name of the load balancer"
  value       = { "Public" = aws_lb.public-elb.dns_name, "Private" = aws_lb.private-elb.dns_name, "DB" = aws_db_instance.database.endpoint }
}
