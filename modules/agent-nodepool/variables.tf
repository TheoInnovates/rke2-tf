variable "name" {
  description = "Nodepool name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to create resources in"
  type        = string
}

variable "subnets" {
  description = "List of subnet IDs to create resources in"
  type        = list(string)
}

variable "instance_type" {
  description = "Node pool instance type"
  default     = "t3.medium"
}

variable "ami" {
  description = "Node pool ami"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Map of additional tags to add to all resources created"
  type        = map(string)
  default     = {}
}

#
# Nodepool Variables
#
variable "iam_instance_profile" {
  description = "Node pool IAM Instance Profile, created if left blank (default behavior)"
  type        = string
  default     = ""
}

variable "iam_permissions_boundary" {
  description = "If provided, the IAM role created for the nodepool will be created with this permissions boundary attached."
  type        = string
  default     = null
}

variable "ssh_authorized_keys" {
  description = "Node pool list of public keys to add as authorized ssh keys, not required"
  type        = list(string)
  default     = []
}

variable "block_device_mappings" {
  description = "Node pool block device mapping configuration"
  type        = map(string)

  default = {
    "size" = 30
    type   = "gp2"
  }
}

variable "extra_cloud_config_config" {
  description = "extra config to append to cloud-config"
  type        = string
  default     = ""
}

variable "extra_block_device_mappings" {
  description = "Used to specify additional block device mapping configurations"
  type        = list(map(string))
  default = [
  ]
}

variable "asg" {
  description = "Node pool AutoScalingGroup scaling definition"
  type = object({
    min                  = number
    max                  = number
    desired              = number
    suspended_processes  = optional(list(string))
    termination_policies = optional(list(string))
  })

  default = {
    min                  = 1
    max                  = 10
    desired              = 1
    suspended_processes  = []
    termination_policies = ["Default"]
  }
}

variable "spot" {
  description = "Toggle spot requests for node pool"
  type        = bool
  default     = false
}

variable "associate_public_ip_address" {
  default = null
  type    = bool
}

variable "target_group_arns" {
  type    = list(string)
  default = []
}

variable "min_elb_capacity" {
  type    = number
  default = null
}

variable "extra_security_group_ids" {
  description = "List of additional security group IDs"
  type        = list(string)
  default     = []
}

variable "metadata_options" {
  type = map(any)
  default = {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDS-v2
    http_put_response_hop_limit = 2          # allow pods to use IMDS as well
    instance_metadata_tags      = "disabled"
  }
  description = "Instance Metadata Options"
}

#
# RKE2 Variables
#
variable "cluster_data" {
  description = "Required data relevant to joining an existing rke2 cluster, sourced from main rke2 module, do NOT modify"

  type = object({
    name       = string
    server_url = string
    cluster_sg = string
    token = object({
      bucket          = string
      bucket_arn      = string
      object          = string
      policy_document = string
    })
  })
}

variable "rke2_channel" {
  description = "Channel to use for RKE2 agent nodepool"
  type        = string
  default     = null
}

variable "rke2_version" {
  description = "Version to use for RKE2 agent nodepool"
  type        = string
  default     = null
}

variable "rke2_config" {
  description = "Node pool additional configuration passed as rke2 config file, see https://docs.rke2.io/install/install_options/agent_config for full list of options"
  default     = ""
}

variable "enable_ccm" {
  description = "Toggle enabling the cluster as aws aware, this will ensure the appropriate IAM policies are present"
  type        = bool
  default     = false
}

variable "enable_autoscaler" {
  description = "Toggle configure the nodepool for cluster autoscaler, this will ensure the appropriate IAM policies are present, you are still responsible for ensuring cluster autoscaler is installed"
  type        = bool
  default     = false
}

variable "download" {
  description = "Toggle best effort download of rke2 dependencies (rke2 and aws cli), if disabled, dependencies are assumed to exist in $PATH"
  type        = bool
  default     = true
}

variable "pre_userdata" {
  description = "Custom userdata to run immediately before rke2 node attempts to join cluster, after required rke2, dependencies are installed"
  type        = string
  default     = ""
}

variable "post_userdata" {
  description = "Custom userdata to run immediately after rke2 node attempts to join cluster"
  type        = string
  default     = ""
}

variable "wait_for_capacity_timeout" {
  description = "How long Terraform should wait for ASG instances to be healthy before timing out."
  type        = string
  default     = "10m"
}

variable "ccm_external" {
  description = "Set kubelet arg 'cloud-provider-name' value to 'external'.  Requires manual install of CCM."
  type        = bool
  default     = false
}

variable "rke2_start" {
  description = "Start/Stop value for the rke2-server/agent service.  True=start, False= don't start."
  type        = bool
  default     = true
}

variable "rke2_install_script_url" {
  description = "URL for RKE2 install script"
  type        = string
  default     = "https://get.rke2.io"
}

variable "awscli_url" {
  description = "URL for awscli zip file"
  type        = string
  default     = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
}

variable "unzip_rpm_url" {
  description = "URL path to unzip rpm"
  type        = string
  default     = ""
}