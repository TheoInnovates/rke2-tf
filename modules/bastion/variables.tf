variable "ami_id" {
  description = "AMI to use for bastion"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets to deploy bastion into"
  type        = list(string)
}

variable "vpc_id" {
  type = string
}

variable "kubeconfig_path_arn" {
  type = string
}

variable "kubeconfig_path" {
  type = string
}

variable "cluster_name" {
  type = string
}