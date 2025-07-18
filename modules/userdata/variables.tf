variable "agent" {
  description = "Toggle server or agent init, defaults to agent"
  type        = bool
  default     = true
}

variable "server_url" {
  description = "rke2 server url"
  type        = string
}

variable "token_bucket" {
  description = "Bucket name where token is located"
  type        = string
}

variable "token_object" {
  description = "Object name of token in bucket"
  type        = string
  default     = "token"
}

variable "config" {
  description = "RKE2 config file yaml contents"
  type        = string
  default     = ""
}

variable "ccm" {
  description = "Toggle cloud controller manager"
  type        = bool
  default     = true
}

variable "ccm_external" {
  description = "Set kubelet arg 'cloud-provider-name' value to 'external'.  Requires manual install of CCM."
  type        = bool
  default     = true
}

#
# Custom Userdata
#
variable "pre_userdata" {
  description = "Custom userdata to run immediately before rke2 node attempts to join cluster, after required rke2, dependencies are installed"
  default     = ""
}

variable "post_userdata" {
  description = "Custom userdata to run immediately after rke2 node attempts to join cluster"
  default     = ""
}

variable "rke2_start" {
  description = "Start/Stop value for the rke2-server/agent service.  This will prevent the service from starting until the next reboot. True=start, False= don't start."
  type        = bool
  default     = true
}
