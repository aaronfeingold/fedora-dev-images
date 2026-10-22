# Fedora dev images (AWS + GCP)

Packer template that builds a ready-to-use **Fedora 44** machine image on **AWS (AMI)** and/or
**GCP (GCE image)** by running the [Fedora dev machine playbook](https://github.com/aaronfeingold/ajf-fedora-workstation-ansible)
against a temporary builder instance. Launch an instance from the image and start building, with no
20-minute setup each time.

Two flavors:

| | `./build aws` | `./build aws --gpu` |
|---|---|---|
| Base tools, Docker, Python/Node, cloud CLIs | ✓ | ✓ |
| NVIDIA driver, CUDA 13.x, container toolkit | | ✓ (loads on first boot of a GPU instance) |
| `~/.venvs/torch`, `~/.venvs/tf` (CUDA builds) | | ✓ |

Images are named `fedora-dev-f44[-gpu]-<timestamp>`; on GCP they also join the image family
`fedora-dev-f44[-gpu]`, so "latest" is always `--image-family fedora-dev-f44-gpu`.

## Prerequisites

```sh
brew install packer ansible            # or: sudo dnf install packer ansible-core (HashiCorp repo)
aws configure    # or aws sso login / AWS_PROFILE=...           (for AWS)
gcloud auth application-default login                            # (for GCP)
export GCP_PROJECT_ID=$(gcloud config get-value project)         # (for GCP)
```

Put the playbook next to this repo (`../ajf-fedora-workstation-ansible`) to build from your local
changes; otherwise `./build` fetches the public repo. Override with `ANSIBLE_DIR` / `ANSIBLE_REPO_URL`.

## Build

```sh
./build aws                 # base AMI in us-east-1
./build gcp --gpu           # GPU image on GCP
./build all --gpu           # both
./build aws -- -var aws_region=us-west-2 -var image_name=acme-dev
```

Per-user settings: copy `example.auto.pkrvars.hcl.example` to `mine.auto.pkrvars.hcl` (gitignored).

## Use an image

```sh
# AWS (GPU): g4dn.xlarge = 1x T4, the cheapest NVIDIA option
aws ec2 run-instances --image-id ami-... --instance-type g4dn.xlarge --key-name my-key ...
ssh fedora@<ip>
nvidia-smi && ~/.venvs/torch/bin/python -c "import torch; print(torch.cuda.is_available())"

# Then layer your personal dotfiles on (from your laptop, in the playbook repo):
DOTFILES_REPO=you/dotfiles ./run_playbook -i <ip>, -u fedora --tags dotfiles
```

Log in as `fedora` on both clouds; the per-user tools (nvm, pyenv, `~/.venvs`) live in that home.

## Secrets and logs

- **No secrets in this repo or the build.** Packer runs Ansible from your machine over SSH, so the
  builder never clones anything (no GitHub token, nothing to leak into logs or the image). Cloud
  credentials come from your AWS profile / gcloud ADC, never Packer variables.
- **Nothing personal is baked in.** Dotfiles, git identity, and keys are applied per user after launch.
- **Builder SSH is locked to your IP** on AWS (`temporary_security_group_source_public_ip`); Packer
  uses throwaway SSH keys and deletes the builder afterwards.
- **The image is scrubbed** before capture: dnf caches, `/tmp`, journal, shell history, the builder's
  `authorized_keys`, and cloud-init state (so each instance gets fresh SSH host keys and your key).
- Don't set `PACKER_LOG=1` in shared CI logs; it is verbose by design.

## Costs

A base build takes ~15 min on a `t3.large` / `e2-standard-4` (cents). GPU images are built on the
same non-GPU instance types; you only pay GPU prices when you launch from the image. Images/snapshots
cost storage per month: delete old ones (`aws ec2 deregister-image`, `gcloud compute images delete`).
