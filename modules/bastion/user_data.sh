#!/bin/bash
set -e

# Install amazon ssm agent
dnf update -y
dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install system dependencies
dnf install -y curl unzip jq bash-completion \
  tar gzip

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
sudo tee /etc/profile.d/add-local-bin.sh > /dev/null <<'EOF'
# Ensure /usr/local/bin is in PATH
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
