# Nothing personal or secret belongs here. Cloud credentials come from your normal
# AWS profile / gcloud application-default login, never from Packer variables.
# Per-user values go in a gitignored *.auto.pkrvars.hcl (see example.auto.pkrvars.hcl.example).

variable "fedora_version" {
  type        = number
  default     = 44
  description = "Fedora release to build from (official Fedora Cloud images)."
}

variable "image_name" {
  type        = string
  default     = "fedora-dev"
  description = "Name prefix for the output AMI / GCE image. A -gpu suffix and timestamp are added."
}

variable "gpu" {
  type        = bool
  default     = false
  description = "Bake NVIDIA driver + CUDA + ML venvs into the image (for GPU instances)."
}

variable "ansible_dir" {
  type        = string
  default     = "../fedora-dev-machine"
  description = "Local checkout of the Ansible repo; Packer runs its playbook from this machine over SSH."
}

variable "ansible_extra_vars" {
  type        = map(string)
  default     = {}
  description = "Extra -e vars for the playbook, e.g. { install_databases = \"true\" }."
}

variable "disk_size_gb" {
  type        = number
  default     = 80
  description = "Root disk size. GPU images with CUDA + PyTorch + TensorFlow need ~60 GB."
}

# ---- AWS ----
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_instance_type" {
  type        = string
  default     = "t3.large"
  description = "Builder instance. A GPU image can be built on a non-GPU instance (driver is installed, loads on first boot of a GPU instance)."
}

# ---- GCP ----
variable "gcp_project_id" {
  type        = string
  default     = env("GCP_PROJECT_ID")
  description = "GCP project to build in. Defaults to $GCP_PROJECT_ID."
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}

variable "gcp_machine_type" {
  type    = string
  default = "e2-standard-4"
}
