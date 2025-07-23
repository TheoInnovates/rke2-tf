variable "cluster_name" {
  description = "Name of the rkegov cluster to create"
  type        = string
  default     = "cloud-enabled"
}

variable "unique_suffix" {
  description = "Enables/disables generation of a unique suffix to cluster name"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Map of tags to add to all resources created"
  default     = {}
  type        = map(string)
}

#
# Server pool variables
#
variable "instance_type" {
  type        = string
  default     = "t3a.medium"
  description = "Server pool instance type"
}

variable "ami" {
  description = "Server pool ami"
  type        = string
  default     = "ami-0dfc569a8686b9320"
}

variable "iam_instance_profile" {
  description = "Server pool IAM Instance Profile, created if left blank (default behavior)"
  type        = string
  default     = ""
}

variable "iam_permissions_boundary" {
  description = "If provided, the IAM role created for the servers will be created with this permissions boundary attached."
  type        = string
  default     = null
}

variable "block_device_mappings" {
  description = "Server pool block device mapping configuration"
  type        = map(string)
  default = {
    "size"      = 30
    "encrypted" = false
  }
}

variable "extra_block_device_mappings" {
  description = "Used to specify additional block device mapping configurations"
  type        = list(map(string))
  default = [
  ]
}

variable "extra_security_group_ids" {
  description = "List of additional security group IDs"
  type        = list(string)
  default     = []
}

variable "servers" {
  description = "Number of servers to create"
  type        = number
  default     = 3
}

variable "spot" {
  description = "Toggle spot requests for server pool"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ssh_authorized_keys" {
  description = "Server pool list of public keys to add as authorized ssh keys"
  type        = list(string)
  default     = []
}

variable "suspended_processes" {
  description = "List of processes to suspend in the autoscaling service"
  type        = list(string)
  default     = []
}

variable "termination_policies" {
  description = "List of policies to decide how the instances in the Auto Scaling Group should be terminated"
  type        = list(string)
  default     = ["Default"]
}

#
# Controlplane Variables
#
variable "controlplane_enable_cross_zone_load_balancing" {
  description = "Toggle between controlplane cross zone load balancing"
  default     = true
  type        = bool
}

variable "controlplane_internal" {
  description = "Toggle between public or private control plane load balancer"
  default     = true
  type        = bool
}

variable "controlplane_allowed_cidrs" {
  description = "Server pool security group allowed cidr ranges"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_allowed_cidrs" {
  description = "Nginx ALB security group allowed cidr ranges"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "controlplane_access_logs_bucket" {
  description = "Bucket name for logging requests to control plane load balancer"
  type        = string
  default     = "disabled"
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
variable "rke2_channel" {
  description = "Channel to use for RKE2 server nodepool"
  type        = string
  default     = null
}

variable "rke2_version" {
  description = "Version to use for RKE2 server nodepool"
  type        = string
  default     = null
}

variable "rke2_config" {
  description = "Server pool additional configuration passed as rke2 config file, see https://docs.rke2.io/install/install_options/server_config for full list of options"
  type        = string
  default     = ""
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

variable "enable_autoscaler" {
  description = "Toggle enabling policies required for cluster autoscaler to work"
  type        = bool
  default     = true
}

variable "enable_ccm" {
  description = "Toggle enabling the cluster as aws aware, this will ensure the appropriate IAM policies are present"
  type        = bool
  default     = true
}

variable "ccm_external" {
  description = "Set kubelet arg 'cloud-provider-name' value to 'external'.  Requires manual install of CCM."
  type        = bool
  default     = true
}

variable "wait_for_capacity_timeout" {
  description = "How long Terraform should wait for ASG instances to be healthy before timing out."
  type        = string
  default     = "10m"
}

variable "associate_public_ip_address" {
  default = null
  type    = bool
}

variable "extra_cloud_config_config" {
  description = "extra config to append to cloud-config"
  type        = string
  default     = ""
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

variable "rke2_start" {
  description = "Start/Stop value for the rke2-server/agent service.  This will prevent the service from starting until the next reboot. True=start, False= don't start."
  type        = bool
  default     = true
}

#
### Statestore Variables
#

variable "statestore_attach_deny_insecure_transport_policy" {
  description = "Toggle for enabling s3 policy to reject non-SSL requests"
  type        = bool
  default     = true
}

variable "create_acl" {
  description = "Toggle creation of ACL for statestore bucket"
  type        = bool
  default     = true
}

variable "alb_enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for the ALB"
  type        = bool
  default     = false
}

variable "alb_access_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  type        = string
  default     = "disabled"
}

variable "alb_internal" {
  description = "Whether the ALB should be internal"
  type        = bool
  default     = false
}

variable "allow_alb_to_cluster" {
  description = "Allow ALB security group to access cluster nodes"
  type        = bool
  default     = true
}

variable "nginx_nodeport" {
  description = "NodePort for nginx service"
  type        = number
  default     = 30080
}

variable "allow_full_nodeport_range" {
  description = "Allow ALB to access full NodePort range (30000-32767)"
  type        = bool
  default     = true
}