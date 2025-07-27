#!/bin/sh

export TYPE="${type}"
export CCM="${ccm}"
export CCM_EXTERNAL="${ccm_external}"

# info logs the given argument at info log level.
info() {
    echo "[INFO] " "$@"
}

# warn logs the given argument at warn log level.
warn() {
    echo "[WARN] " "$@" >&2
}

# fatal logs the given argument at fatal log level.
fatal() {
    echo "[ERROR] " "$@" >&2
    exit 1
}

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

config() {
  mkdir -p "/etc/rancher/rke2"
  cat <<EOF >> "/etc/rancher/rke2/config.yaml"
# Additional user defined configuration
${config}
EOF
}

append_config() {
  echo "$1" >> "/etc/rancher/rke2/config.yaml"
}

append_config_san() {
  grep "^tls-san:$" /etc/rancher/rke2/config.yaml > /dev/null
  if [ $? -eq 0 ]; then
    sed -i "/^tls-san:$/a \ \ - ${server_url}" /etc/rancher/rke2/config.yaml
    return
  fi
  echo "tls-san:" >> /etc/rancher/rke2/config.yaml
  echo "  - ${server_url}" >> /etc/rancher/rke2/config.yaml
}

# Configure nginx ingress for NLB
configure_nginx_nlb() {
  info "Configuring nginx ingress for NLB"
  
  mkdir -p "/var/lib/rancher/rke2/server/manifests"
  
  cat <<EOF > "/var/lib/rancher/rke2/server/manifests/nginx-nlb-config.yaml"
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-ingress-nginx
  namespace: kube-system
spec:
  valuesContent: |
    controller:
      # Change from DaemonSet to Deployment for LoadBalancer
      kind: Deployment
      replicaCount: ${nginx_replica_count}
      
      # Disable hostNetwork so it can work with LoadBalancer
      hostNetwork: false
      
      service:
        enabled: true
        type: LoadBalancer
        annotations:
          # Core NLB configuration
          service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
          service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
          service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
          service.beta.kubernetes.io/aws-load-balancer-scheme: "${nlb_scheme}"
          
          # Health checks
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "tcp"
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "traffic-port"
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval-seconds: "10"
          service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout-seconds: "6"
          service.beta.kubernetes.io/aws-load-balancer-healthy-threshold-count: "2"
          service.beta.kubernetes.io/aws-load-balancer-unhealthy-threshold-count: "2"
          
          # Performance optimizations
          service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "deregistration_delay.timeout_seconds=60,preserve_client_ip.enabled=true"
          
          # Specify subnets
          service.beta.kubernetes.io/aws-load-balancer-subnets: "${public_subnets}"
          
      # Configure nginx to handle real client IPs
      config:
        use-forwarded-headers: "true"
        compute-full-forwarded-for: "true"
        use-proxy-protocol: "false"
        enable-real-ip: "true"
        real-ip-header: "X-Forwarded-For"
        real-ip-recursive: "true"
        # Performance tuning
        worker-processes: "auto"
        worker-connections: "16384"
        max-worker-open-files: "65536"
        # SSL configuration
        ssl-protocols: "TLSv1.2 TLSv1.3"
        ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"
        
      # Resource limits
      resources:
        limits:
          cpu: "${nginx_cpu_limit}"
          memory: "${nginx_memory_limit}"
        requests:
          cpu: "${nginx_cpu_request}"
          memory: "${nginx_memory_request}"
          
      # Node placement
      nodeSelector:
        kubernetes.io/os: linux
        
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
          
      # Anti-affinity for better distribution
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                  - ingress-nginx
              topologyKey: kubernetes.io/hostname
              
      # Metrics configuration
      metrics:
        enabled: true
        serviceMonitor:
          enabled: false
        prometheusRule:
          enabled: false
          
      # Additional configurations
      extraArgs:
        default-ssl-certificate: "kube-system/nginx-tls"
        
    # Default backend configuration
    defaultBackend:
      enabled: true
      image:
        tag: "1.5"
      resources:
        limits:
          cpu: 10m
          memory: 20Mi
        requests:
          cpu: 10m
          memory: 20Mi
EOF

  info "Nginx NLB configuration created"
}

# Wait for nginx ingress to be ready
wait_for_nginx() {
  info "Waiting for nginx ingress controller to be ready..."
  
  export PATH=$PATH:/var/lib/rancher/rke2/bin
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  
  # Wait for the deployment to exist
  timeout 300 bash -c 'until kubectl get deployment -n kube-system rke2-ingress-nginx-controller 2>/dev/null; do sleep 10; done'
  
  if [ $? -eq 0 ]; then
    info "Nginx ingress controller deployment found"
    
    # Wait for the deployment to be ready
    kubectl rollout status deployment/rke2-ingress-nginx-controller -n kube-system --timeout=300s
    
    if [ $? -eq 0 ]; then
      info "Nginx ingress controller is ready"
      
      # Wait for LoadBalancer to get external IP
      info "Waiting for LoadBalancer to get external IP..."
      timeout 300 bash -c 'until kubectl get svc -n kube-system rke2-ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" | grep -v "^$"; do sleep 10; done'
      
      if [ $? -eq 0 ]; then
        nlb_hostname=$(kubectl get svc -n kube-system rke2-ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
        info "Nginx ingress NLB is ready: $nlb_hostname"
      else
        warn "Timeout waiting for LoadBalancer external IP"
      fi
    else
      warn "Nginx ingress controller deployment failed to become ready"
    fi
  else
    warn "Timeout waiting for nginx ingress controller deployment"
  fi
}

# The most simple "leader election" you've ever seen in your life
elect_leader() {
  # Fetch other running instances in ASG
  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  instance_id=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
  asg_name=$(aws autoscaling describe-auto-scaling-instances --instance-ids "$instance_id" --query 'AutoScalingInstances[*].AutoScalingGroupName' --output text)
  instances=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name "$asg_name" --query 'AutoScalingGroups[*].Instances[?HealthStatus==`Healthy`].InstanceId' --output text)

  # Simply identify the leader as the first of the instance ids sorted alphanumerically
  leader=$(echo $instances | tr ' ' '\n' | sort -n | head -n1)

  info "Current instance: $instance_id | Leader instance: $leader"

  if [ "$instance_id" = "$leader" ]; then
    SERVER_TYPE="leader"
    info "Electing as cluster leader"
  else
    info "Electing as joining server"
  fi
}

identify() {
  # Default to server
  SERVER_TYPE="server"

  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  supervisor_status=$(curl --write-out '%%{http_code}' -sk --output /dev/null https://${server_url}:9345/ping)

  if [ "$supervisor_status" -ne 200 ]; then
    info "API server unavailable, performing simple leader election"
    elect_leader
  else
    info "API server available, identifying as server joining existing cluster"
  fi
}

cp_wait() {
  while true; do
    supervisor_status=$(curl --write-out '%%{http_code}' -sk --output /dev/null https://${server_url}:9345/ping)
    if [ "$supervisor_status" -eq 200 ]; then
      info "Cluster is ready"

      # Let things settle down for a bit, not required
      # TODO: Remove this after some testing
      sleep 10
      break
    fi
    info "Waiting for cluster to be ready..."
    sleep 10
  done
}

local_cp_api_wait() {
  export PATH=$PATH:/var/lib/rancher/rke2/bin
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

  while true; do
    info "$(timestamp) Waiting for kube-apiserver..."
    if timeout 1 bash -c "true <>/dev/tcp/localhost/6443" 2>/dev/null; then
        break
    fi
    sleep 5
  done

  wait $!

  nodereadypath='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'
  until kubectl get nodes --selector='node-role.kubernetes.io/master' -o jsonpath="$nodereadypath" | grep -E "Ready=True"; do
    info "$(timestamp) Waiting for servers to be ready..."
    sleep 5
  done

  info "$(timestamp) all kube-system deployments are ready!"
}

fetch_token() {
  info "Fetching rke2 join token..."

  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  aws configure set default.region "$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)"

  # Validate aws caller identity, fatal if not valid
  if ! aws sts get-caller-identity 2>/dev/null; then
    fatal "No valid aws caller identity"
  fi

  # Either
  #   a) fetch token from s3 bucket
  #   b) fail
  echo ${token_object}
  if token=$(aws s3 cp "s3://${token_object}" - 2>/dev/null);then
    
    info "Found token from s3 object"
  else
    fatal "Could not find cluster token from s3"
  fi

  echo "token: $${token}" >> "/etc/rancher/rke2/config.yaml"
}

upload() {
  # Wait for kubeconfig to exist, then upload to s3 bucket
  retries=10

  while [ ! -f /etc/rancher/rke2/rke2.yaml ]; do
    sleep 10
    if [ "$retries" = 0 ]; then
      fatal "Failed to create kubeconfig"
    fi
    ((retries--))
  done

  # Replace localhost with server url and upload to s3 bucket
  sed "s/127.0.0.1/${server_url}/g" /etc/rancher/rke2/rke2.yaml | aws s3 cp - "s3://${token_bucket}/rke2.yaml" --content-type "text/yaml"
}

{
  info "Beginning rke2-init userdata"
  config
  fetch_token

  if [ $CCM = "true" ]; then
    append_config 'cloud-provider-name: "external"'
    append_config 'disable-cloud-controller: "true"'
  fi
  
  # Disable rke2-servicelb to avoid conflicts with NLB
  append_config 'disable:'
  append_config '  - rke2-servicelb'

  systemctl is-enabled --quiet nm-cloud-setup && \
    systemctl disable nm-cloud-setup; systemctl disable nm-cloud-setup.timer

  if [ $TYPE = "server" ]; then
    # Initialize server
    identify

    append_config_san

    # Configure nginx NLB for all server types
    configure_nginx_nlb

    if [ $SERVER_TYPE = "server" ]; then     # additional server joining an existing cluster
      append_config 'server: https://${server_url}:9345'
      # Wait for cluster to exist, then init another server
      cp_wait
    fi
    systemctl restart rke2-server
    systemctl enable rke2-server
    systemctl daemon-reload

    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    export PATH=$PATH:/var/lib/rancher/rke2/bin

    if [ $SERVER_TYPE = "leader" ]; then
      systemctl start rke2-server

      # Upload kubeconfig to s3 bucket
      upload

      # For servers, wait for apiserver to be ready before continuing so that `post_userdata` can operate on the cluster
      local_cp_api_wait
      
      # Wait for nginx ingress to be ready (only on leader)
      wait_for_nginx
      
    elif ${rke2_start}; then
      systemctl start rke2-server
    fi

  else
    append_config 'server: https://${server_url}:9345'

    # Default to agent
    systemctl restart rke2-agent
    systemctl enable rke2-agent
    systemctl daemon-reload
    if ${rke2_start}; then
      systemctl start rke2-agent
    fi
  fi
  info "Ending rke2-init userdata"

}