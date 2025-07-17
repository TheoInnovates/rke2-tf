data "aws_region" "current" {}

data "aws_iam_policy_document" "ssm_session" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssm:DescribeInstanceInformation",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands",
      "ssm:SendCommand",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:DescribeSessions",
      "ssm:GetSession",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2:DescribeInstances"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "s3_get_object" {
  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${var.kubeconfig_path_arn}"
    ]

    effect = "Allow"
  }
}
