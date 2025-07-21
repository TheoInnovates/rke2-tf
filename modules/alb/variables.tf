variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "internal" {
  default = true
  type    = bool
}

variable "enable_cross_zone_load_balancing" {
  default = true
  type    = bool
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "access_logs_bucket" {
  type    = string
  default = "disabled"
}

variable "alb_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB"
  type        = list(string)
}