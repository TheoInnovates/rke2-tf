resource "aws_iam_role" "bastion" {
  name = "bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}


resource "aws_iam_role_policy" "get_token" {

  name   = "bastion-rke2-agent-aws-get-token"
  role   = aws_iam_role.bastion.id
  policy = data.aws_iam_policy_document.s3_get_object.json
}

resource "aws_iam_role_policy" "ssm_session" {
  name   = "bastion-rke2-agent-aws-ssm-session"
  role   = aws_iam_role.bastion.id
  policy = data.aws_iam_policy_document.ssm_session.json
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "bastion-instance-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_launch_template" "bastion" {
  name_prefix   = "bastion-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile { name = aws_iam_instance_profile.bastion_profile.name }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.bastion.id]
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
  kubeconfig_path = var.kubeconfig_path }))

}

resource "aws_autoscaling_group" "bastion" {
  name                = "bastion-asg"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.bastion.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "bastion"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "bastion" {
  name        = "bastion-sg"
  description = "Security group for Bastion host"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "bastion-sg"
  }
}