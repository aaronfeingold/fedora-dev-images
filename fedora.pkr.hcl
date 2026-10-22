packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
    googlecompute = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/googlecompute"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmm", timestamp())
  name      = "${var.image_name}-f${var.fedora_version}${var.gpu ? "-gpu" : ""}-${local.timestamp}"

  # Settings for the playbook. Dotfiles are per-user, so they're applied when someone uses
  # the instance (./run_playbook --tags dotfiles), never baked into a shared image.
  ansible_vars = merge(
    {
      dotfiles_repo      = ""
      install_cloud_clis = "true"
      install_gui        = "false"
      gpu_force          = "${var.gpu}"
      install_ml         = "${var.gpu}"
      gpu_allow_reboot   = "false"
    },
    var.ansible_extra_vars,
  )
}

# ---- AWS: latest official Fedora Cloud AMI (Fedora Project's account) ----
source "amazon-ebs" "fedora" {
  region        = var.aws_region
  instance_type = var.aws_instance_type
  ami_name      = local.name
  ssh_username  = "fedora"

  source_ami_filter {
    owners      = ["125523088429"] # Fedora Project
    most_recent = true
    filters = {
      name                = "Fedora-Cloud-Base-AmazonEC2.x86_64-${var.fedora_version}-*"
      architecture        = "x86_64"
      virtualization-type = "hvm"
    }
  }

  # Only your current public IP can SSH to the temporary builder (default would be 0.0.0.0/0).
  temporary_security_group_source_public_ip = true

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.disk_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name          = local.name
    FedoraVersion = var.fedora_version
    GPU           = var.gpu
    Builder       = "packer"
  }
}

# ---- GCP: latest official Fedora Cloud image ----
source "googlecompute" "fedora" {
  project_id              = var.gcp_project_id
  zone                    = var.gcp_zone
  machine_type            = var.gcp_machine_type
  source_image_family     = "fedora-cloud-${var.fedora_version}-x86-64"
  source_image_project_id = ["fedora-cloud"]
  image_name              = local.name
  image_family            = "${var.image_name}-f${var.fedora_version}${var.gpu ? "-gpu" : ""}"
  disk_size               = var.disk_size_gb
  # Same login user as AWS, so per-user tools (nvm, pyenv, ~/.venvs) are in the home you log into.
  ssh_username = "fedora"
  image_labels = {
    fedora_version = "${var.fedora_version}"
    gpu            = "${var.gpu}"
    builder        = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.fedora", "source.googlecompute.fedora"]

  # Runs ansible-playbook on THIS machine against the builder over SSH: nothing is cloned onto
  # the instance, so no GitHub token is needed and none can end up in logs or the image.
  provisioner "ansible" {
    playbook_file   = "${var.ansible_dir}/playbook.yml"
    user            = build.User
    groups          = [var.gpu ? "gpu_cloud" : "cloud"]
    use_proxy       = false
    extra_arguments = flatten([for k, v in local.ansible_vars : ["-e", "${k}=${v}"]])
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${var.ansible_dir}/ansible.cfg",
      "ANSIBLE_ROLES_PATH=${var.ansible_dir}/roles",
      "ANSIBLE_HOST_KEY_CHECKING=False",
    ]
  }

  # Leave a clean image: no caches, logs, histories, or this build's cloud-init state/SSH keys.
  provisioner "shell" {
    inline = [
      "sudo dnf clean all",
      "sudo rm -rf /tmp/* /var/tmp/* ~/.ansible ~/.cache",
      "sudo journalctl --rotate && sudo journalctl --vacuum-time=1s",
      "sudo cloud-init clean --logs --seed",
      "rm -f ~/.bash_history ~/.zsh_history ~/.ssh/authorized_keys",
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
