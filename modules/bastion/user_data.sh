#!/bin/bash
set -e

# Install amazon ssm agent
dnf update -y
dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install system dependencies
dnf install -y curl unzip jq bash-completion tar gzip

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl

# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Add local bin to PATH
sudo tee /etc/profile.d/add-local-bin.sh > /dev/null <<'EOF'
case ":$PATH:" in
  *:/usr/local/bin:*) ;;
  *) export PATH="$PATH:/usr/local/bin" ;;
esac
EOF
sudo chmod +x /etc/profile.d/add-local-bin.sh
source /etc/profile.d/add-local-bin.sh

# Enable kubectl autocomplete
echo 'source <(kubectl completion bash)' >> /etc/bashrc
echo 'alias k=kubectl' >> /etc/bashrc
echo 'complete -o default -F __start_kubectl k' >> /etc/bashrc

# Fetch kubeconfig from S3
mkdir -p ~/.kube
aws s3 cp ${kubeconfig_path} ~/.kube/config
chmod 600 ~/.kube/config

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
wait_for_cluster_ready() {
  local max_attempts=60
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if kubectl get nodes >/dev/null 2>&1; then
      echo "Cluster is responsive, checking node readiness..."
      
      # Wait for at least one control-plane node to be Ready
      if kubectl get nodes --selector='node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | grep "Ready"; then
        echo "Control plane nodes are ready!"
        return 0
      fi
    fi
    
    echo "Waiting for cluster... (attempt $((attempt + 1))/$max_attempts)"
    sleep 30
    attempt=$((attempt + 1))
  done
  
  echo "Timeout waiting for cluster to be ready"
  return 1
}

# Install AWS Cloud Controller Manager with proper error handling
install_ccm() {
  echo "Installing AWS Cloud Controller Manager..."
  
  # Add repository with retry logic
  local max_retries=3
  local retry=0
  
  while [ $retry -lt $max_retries ]; do
    if helm repo add aws-cloud-controller-manager https://kubernetes.github.io/cloud-provider-aws; then
      echo "Helm repo added successfully"
      break
    else
      echo "Failed to add helm repo, retrying... ($((retry + 1))/$max_retries)"
      sleep 10
      retry=$((retry + 1))
    fi
  done
  
  if [ $retry -eq $max_retries ]; then
    echo "Failed to add helm repository after $max_retries attempts"
    return 1
  fi
  
  helm repo update
  
  # Check if CCM is already installed
  if helm list -n kube-system | grep -q aws-cloud-controller-manager; then
    echo "AWS Cloud Controller Manager already installed, skipping..."
    return 0
  fi
  
  # Install CCM with all necessary tolerations
  helm install aws-cloud-controller-manager aws-cloud-controller-manager/aws-cloud-controller-manager \
    --namespace kube-system \
    --timeout 10m \
    --wait \
    --set-json 'args=["--v=2", "--cloud-provider=aws", "--allocate-node-cidrs=false", "--configure-cloud-routes=false"]' \
    --set nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set tolerations[0].operator="Exists" \
    --set tolerations[0].effect="NoSchedule" \
    --set tolerations[1].key="node-role.kubernetes.io/master" \
    --set tolerations[1].operator="Exists" \
    --set tolerations[1].effect="NoSchedule" \
    --set tolerations[2].key="node.cloudprovider.kubernetes.io/uninitialized" \
    --set tolerations[2].operator="Exists" \
    --set tolerations[2].effect="NoSchedule"
  
  if [ $? -eq 0 ]; then
    echo "AWS Cloud Controller Manager installed successfully"
    
    # Wait for CCM pods to be running
    echo "Waiting for CCM pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=aws-cloud-controller-manager -n kube-system --timeout=300s
    
    # Monitor node initialization
    echo "Monitoring node initialization..."
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
      # Check if any nodes still have the uninitialized taint
      local uninitialized_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[?(@.key=="node.cloudprovider.kubernetes.io/uninitialized")]}{"\n"}{end}' | grep "uninitialized" | wc -l)
      
      if [ "$uninitialized_nodes" -eq 0 ]; then
        echo "All nodes have been initialized by CCM!"
        break
      fi
      
      echo "Still waiting for $uninitialized_nodes nodes to be initialized... ($wait_count/30)"
      sleep 10
      wait_count=$((wait_count + 1))
    done
  else
    echo "Failed to install AWS Cloud Controller Manager"
    return 1
  fi
}

# Install Cluster Autoscaler
install_cluster_autoscaler() {
  echo "Installing Cluster Autoscaler..."
  
  helm repo add autoscaler https://kubernetes.github.io/autoscaler
  helm repo update
  
  # Check if already installed
  if helm list -n kube-system | grep -q autoscaler; then
    echo "Cluster Autoscaler already installed, skipping..."
    return 0
  fi
  
  helm install autoscaler autoscaler/cluster-autoscaler \
    --namespace kube-system \
    --timeout 10m \
    --wait \
    --set autoDiscovery.clusterName=${cluster_name} \
    --set awsRegion=${aws_region} \
    --set nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set tolerations[0].operator="Exists" \
    --set tolerations[0].effect="NoSchedule" \
    --set tolerations[1].key="node-role.kubernetes.io/master" \
    --set tolerations[1].operator="Exists" \
    --set tolerations[1].effect="NoSchedule"
  
  echo "Cluster Autoscaler installation completed"
}

# Install cert-manager
install_cert_manager() {
  echo "Installing cert-manager..."
  
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  
  if helm list -n cert-manager | grep -q cert-manager; then
    echo "cert-manager already installed, skipping..."
    return 0
  fi
  
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.13.0 \
    --timeout 10m \
    --wait \
    --set installCRDs=true \
    --set nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set tolerations[0].operator="Exists" \
    --set tolerations[0].effect="NoSchedule" \
    --set tolerations[1].key="node-role.kubernetes.io/master" \
    --set tolerations[1].operator="Exists" \
    --set tolerations[1].effect="NoSchedule"
  
  echo "cert-manager installation completed"
}

# Install AWS Load Balancer Controller
install_alb_controller() {
  echo "Installing AWS Load Balancer Controller..."
  
  helm repo add eks https://aws.github.io/eks-charts
  helm repo update
  
  if helm list -n kube-system | grep -q aws-load-balancer-controller; then
    echo "AWS Load Balancer Controller already installed, skipping..."
    return 0
  fi
  
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --timeout 10m \
    --wait \
    --set clusterName=${cluster_name} \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=${aws_region} \
    --set nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
    --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set tolerations[0].operator="Exists" \
    --set tolerations[0].effect="NoSchedule" \
    --set tolerations[1].key="node-role.kubernetes.io/master" \
    --set tolerations[1].operator="Exists" \
    --set tolerations[1].effect="NoSchedule"
  
  echo "AWS Load Balancer Controller installation completed"
}

# Execute installations in order
{
  echo "Starting cluster component installations..."
  
  if wait_for_cluster_ready; then
    echo "Cluster is ready, proceeding with installations..."
    
    # Install components in the correct order
    install_ccm
    sleep 30  # Give CCM time to initialize nodes
    
    install_cluster_autoscaler
    install_cert_manager
    install_alb_controller
    
    echo "All installations completed successfully!"
    
    # Final status check
    echo "Final cluster status:"
    kubectl get nodes -o wide
    kubectl get pods -n kube-system
    
  else
    echo "Cluster not ready after timeout, skipping installations"
    exit 1
  fi
} 2>&1 | tee /var/log/bastion-setup.log