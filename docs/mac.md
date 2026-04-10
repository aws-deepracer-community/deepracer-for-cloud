# Running DeepRacer-for-Cloud on macOS

DRfC can be run on macOS, both on AWS Mac EC2 instances (mac1/mac2 family) and on local Mac hardware (Intel or Apple Silicon). Because macOS does not support NVIDIA GPUs, training always runs in **CPU mode**.

---

## Architecture overview

On macOS, Docker containers run inside a lightweight Linux VM managed by [Colima](https://github.com/abiosoft/colima) rather than directly on the host. This has a few implications you should be aware of:

| Concern | Impact |
|---|---|
| **No NVIDIA GPU** | Always `cpu` architecture; training is slower than a GPU instance |
| **Colima VM filesystem** | Bind-mount paths (e.g. `/tmp/sagemaker`) must exist inside the VM, not on the macOS host |
| **IMDS not reachable from VM** | IAM role credentials are not automatically available inside containers; explicit AWS keys must be configured |
| **BSD userland** | `sed`, `grep`, `sort`, `readlink` differ from GNU; scripts have been adapted |
| **bash 3.2 ships with macOS** | A modern bash 5 must be installed via Homebrew and set as the login shell |

---

## Option 1: AWS Mac EC2 instance

AWS offers bare-metal Mac instances (`mac1.metal` for Intel, `mac2.metal` / `mac2-m2.metal` for Apple Silicon). These run macOS natively and support EC2 features like IAM roles, S3, and instance metadata — with the IMDS caveat noted above.

### Prerequisites

* A Mac EC2 instance running macOS Monterey (12) or later
* An IAM role or IAM user with permissions for S3 (and optionally STS, CloudWatch)
* An S3 bucket in the same region as the instance

### Step 1 — Clone the repository

```bash
git clone https://github.com/aws-deepracer-community/deepracer-for-cloud.git
cd deepracer-for-cloud
```

### Step 2 — Run prepare-mac.sh

```bash
bash bin/prepare-mac.sh
```

This script will:

1. Verify macOS version compatibility
2. Install [Homebrew](https://brew.sh) if not present
3. Install required packages: `jq`, `python3`, `git`, `screen`, `bash`
4. Install bash 5 and set it as the default login shell
5. Add a `~/.bash_profile` bootstrap so bash 5 is used even when SSH starts `/bin/bash` (3.2)
6. Install the AWS CLI v2 via the official `.pkg` installer (avoids Homebrew Python conflicts)
7. Install [Colima](https://github.com/abiosoft/colima) and the Docker CLI
8. Start Colima (4 vCPUs, 8 GB RAM, 60 GB disk — adjust as needed)
9. Create `/tmp/sagemaker` inside the Colima VM
10. Install a launchd agent so Colima auto-starts on login

After the script completes, **log out and back in** so the new default shell takes effect.

### Step 3 — Configure AWS credentials

Because containers run inside Colima's Linux VM, they cannot reach the EC2 Instance Metadata Service at `169.254.169.254`. You must provide explicit AWS credentials:

```bash
aws configure --profile default
```

Enter an Access Key ID and Secret Access Key for an IAM user (or long-term credentials). The profile name must match `DR_LOCAL_S3_PROFILE` in `system.env` (default: `default` for AWS cloud setups).

> **Tip:** Create a dedicated IAM user with a policy scoped to your S3 bucket rather than using root or overly broad credentials.

### Step 4 — Run init.sh

```bash
bin/init.sh -c aws -a cpu
```

This sets up the directory structure, configures `system.env` and `run.env`, and pulls the Docker images. Image pulls may take a while depending on bandwidth.

### Step 5 — Activate and train

```bash
source bin/activate.sh
dr-upload-custom-files
dr-start-training -q
```

---

## Option 2: Local Mac (desktop/laptop)

Running DRfC locally on a Mac works for development and small-scale training. Performance is limited by CPU speed and memory.

### Differences from EC2

* No IAM role — configure an IAM user with `aws configure`
* `DR_CLOUD` should be set to `local` in `system.env`, which uses a local MinIO container as the S3 backend
* Colima memory and CPU limits should be tuned to your machine (leave headroom for the macOS host)

### Recommended Colima sizing

| Mac | Recommended Colima config |
|---|---|
| M1/M2/M3 with 16 GB RAM | `--cpu 6 --memory 10 --disk 60` |
| M1/M2/M3 with 32 GB RAM | `--cpu 10 --memory 20 --disk 60` |
| Intel with 16 GB RAM | `--cpu 4 --memory 8 --disk 60` |

To change the sizing after initial setup:

```bash
colima stop
colima start --cpu 6 --memory 10 --disk 60
```

### Apple Silicon (arm64) and container image architecture

The DRfC SimApp images are built for `amd64` (x86_64). On Apple Silicon, Colima runs them via emulation. This works but is slower. To enable it:

```bash
# Install Rosetta 2 if not already present
softwareupdate --install-rosetta

# Start Colima with x86_64 architecture
colima stop
colima start --arch x86_64 --cpu 4 --memory 8 --disk 60
```

> Note: Once Colima is started with `--arch x86_64`, it stays in that mode until deleted. You cannot mix architectures in the same Colima instance.

### Installation steps

```bash
git clone https://github.com/aws-deepracer-community/deepracer-for-cloud.git
cd deepracer-for-cloud
bash bin/prepare-mac.sh
# Log out and back in
bin/init.sh -c local -a cpu
source bin/activate.sh
dr-upload-custom-files
dr-start-training -q
```

---

## Known limitations

| Limitation | Notes |
|---|---|
| CPU-only training | No NVIDIA GPU support on macOS |
| IMDS not reachable from containers | Must use explicit AWS keys; IAM role auto-rotation does not work inside containers |
| `/tmp/sagemaker` must exist in Colima VM | Created automatically by `prepare-mac.sh` and `dr-start-training`; recreate manually after `colima delete` with `colima ssh -- sudo mkdir -p /tmp/sagemaker && colima ssh -- sudo chmod -R a+w /tmp/sagemaker` |
| Colima iptables rules reset on restart | Not relevant with the explicit-keys approach |
| `brew services` fails headlessly | Colima is started via a launchd plist instead |

---

## Troubleshooting

**`bash: ${VAR,,}: bad substitution`**  
You are running bash 3.2 (macOS built-in). Run `prepare-mac.sh` to install bash 5, then log out and back in.

**`No configuration file.`** when sourcing `activate.sh`  
`init.sh` has not been run yet, or `run.env` does not exist. Run `bin/init.sh` first.

**`docker: command not found`**  
Homebrew PATH is not set. Ensure `~/.bash_profile` contains `eval "$(brew shellenv)"` and re-source it.

**`NoCredentialsError: Unable to locate credentials`**  
Containers cannot reach IMDS. Run `aws configure --profile default` (or the profile matching `DR_LOCAL_S3_PROFILE`) on the host.

**Colima fails to start**  
Check `colima status` and `colima start` output. On freshly allocated Mac EC2 instances the full macOS desktop session may still be initialising — wait a minute and retry.
