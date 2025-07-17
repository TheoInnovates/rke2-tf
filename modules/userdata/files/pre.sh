#!/bin/sh

export TYPE="${type}"
export CCM="${ccm}"

# info logs the given argument at info log level.
info() {
    echo "[INFO] " "$@"
}

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

pre_userdata() {
  info "Beginning user defined pre userdata"
  ${pre_userdata}
  info "Ending user defined pre userdata"
}

install_ssm_agent() {
  info "Installing SSM Agent on RHEL 9"

  sudo dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm

  sudo systemctl enable amazon-ssm-agent
  sudo systemctl start amazon-ssm-agent

  info "SSM Agent installation complete"
}

{
  pre_userdata
  install_ssm_agent
}
