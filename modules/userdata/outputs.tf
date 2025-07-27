output "rke2_templated" {
  value = templatefile("${path.module}/files/rke2-init.sh", {
    type = var.agent ? "agent" : "server"

    server_url   = var.server_url
    token_bucket = var.token_bucket
    token_object = var.token_object
    config       = var.config
    ccm          = var.ccm
    ccm_external = var.ccm_external

    pre_userdata  = var.pre_userdata
    post_userdata = var.post_userdata
    nginx_replica_count  = var.nginx_replica_count
    nlb_scheme          = var.nlb_scheme
    nginx_cpu_limit     = var.nginx_cpu_limit
    nginx_memory_limit  = var.nginx_memory_limit
    nginx_cpu_request   = var.nginx_cpu_request
    nginx_memory_request = var.nginx_memory_request
    public_subnets = var.public_subnets

    rke2_start = var.rke2_start
  })
}
output "pre_templated" {
  value = templatefile("${path.module}/files/pre.sh", {
    type = var.agent ? "agent" : "server"

    server_url   = var.server_url
    token_bucket = var.token_bucket
    token_object = var.token_object
    config       = var.config
    ccm          = var.ccm
    ccm_external = var.ccm_external

    pre_userdata  = var.pre_userdata
    post_userdata = var.post_userdata

    rke2_start = var.rke2_start
  })
}
output "post_templated" {
  value = templatefile("${path.module}/files/post.sh", {
    type = var.agent ? "agent" : "server"

    server_url   = var.server_url
    token_bucket = var.token_bucket
    token_object = var.token_object
    config       = var.config
    ccm          = var.ccm
    ccm_external = var.ccm_external

    pre_userdata  = var.pre_userdata
    post_userdata = var.post_userdata

    rke2_start = var.rke2_start
  })
}
