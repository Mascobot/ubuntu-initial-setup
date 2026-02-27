#!/usr/bin/env bash
set -e

# ============================================
#  Secure Ubuntu Server Setup + UV + Jupyter
# ============================================

# --- Colors and helpers ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERR]${NC} $1"; }

# --- Preflight checks ---
if [[ $(id -u) -ne 0 ]]; then
  print_error "Please run as root (use: sudo $0)"
  exit 1
fi
if grep -qi Microsoft /proc/version; then
  print_error "Running inside WSL is not supported"
  exit 1
fi

echo -e "${GREEN}Starting secure Ubuntu setup...${NC}"

# --- Ask SSH port ---
DEFAULT_SSH_PORT=22
read -e -p "Enter SSH port [default: 22, e.g. 2222]: " SSH_PORT
SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}

# --- Ensure /root/.ssh exists (Hetzner already injects key) ---
mkdir -p /root/.ssh
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
cat << 'EOF' > /root/.ssh/config
Host *
  ServerAliveInterval 60
  StrictHostKeyChecking no
EOF
chmod 600 /root/.ssh/config

# --- System updates & essentials ---
print_status "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qy
apt-get upgrade -qy
apt-get install -qy vim nano tmux curl git htop btop ufw fail2ban unattended-upgrades python3-pip

# --- Install uv (Astral Python manager) ---
print_status "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc
export PATH="$HOME/.local/bin:$PATH"

# --- Enable unattended-upgrades (no auto reboot) ---
cat << 'EOF' > /etc/apt/apt.conf.d/51unattended-upgrades-local
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable unattended-upgrades

# --- Harden SSH ---
print_status "Hardening SSH..."
SSH_CONFIG="/etc/ssh/sshd_config"
perl -ni.bak -e 'print unless /^\s*(PermitEmptyPasswords|PermitRootLogin|PasswordAuthentication|ChallengeResponseAuthentication|Port)/' "$SSH_CONFIG"
cat << EOF >> "$SSH_CONFIG"
Port $SSH_PORT
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
PermitRootLogin prohibit-password
EOF
systemctl reload ssh || systemctl restart ssh

# --- Firewall & Fail2Ban ---
print_status "Configuring firewall and fail2ban..."
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp comment 'SSH access'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 5000/tcp comment 'Jupyter Notebook'
ufw limit $SSH_PORT/tcp comment 'Rate-limit SSH brute-force'
ufw --force enable

systemctl enable fail2ban
systemctl start fail2ban
cat << 'EOF' > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 1h
findtime = 10m
EOF
systemctl restart fail2ban

# ============================================
#  Python + UV + Jupyter Environment Setup
# ============================================

print_status "Setting up UV project and Jupyter environment..."

WORKDIR="/root/uv_project"
if [ -d "$WORKDIR" ]; then
  print_warning "Existing project found at $WORKDIR — removing it..."
  rm -rf "$WORKDIR"
fi
mkdir -p "$WORKDIR" && cd "$WORKDIR"

# Initialize UV project
uv init uv_project
cd uv_project

# Install Python via uv
if ! uv python install 3.12; then
  print_warning "Python 3.12 unavailable — trying 3.11..."
  uv python install 3.11 || uv python install
fi
PY_VERSION=$(uv python list | grep '^\*' | awk '{print $2}' | head -1)
if [[ -n "$PY_VERSION" ]]; then uv python pin "$PY_VERSION"; fi

uv sync
uv add jupyter notebook

# Activate env
source .venv/bin/activate

# --- Configure Jupyter ---
print_status "Configuring Jupyter..."
mkdir -p /root/.jupyter
cat > /root/.jupyter/jupyter_notebook_config.py << 'EOF'
c = get_config()
c.NotebookApp.ip = '*'
c.NotebookApp.open_browser = False
c.NotebookApp.port = 5000
c.NotebookApp.allow_remote_access = True
c.NotebookApp.allow_origin = '*'
EOF

# --- Start Jupyter in tmux ---
print_status "Starting Jupyter in tmux..."
tmux kill-session -t jupyter 2>/dev/null || true
tmux new-session -d -s jupyter "cd $(pwd) && source .venv/bin/activate && jupyter notebook --port 5000 --no-browser --allow-root 2>&1 | tee jupyter.log"

sleep 5
TOKEN=$(grep -o 'token=[a-z0-9]*' jupyter.log | tail -1 | cut -d'=' -f2)

# --- Summary ---
echo ""
echo "=============================================="
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "=============================================="
echo "SSH Port: $SSH_PORT (key-only, root allowed)"
echo "Firewall: Enabled (22/80/443/5000 open)"
echo "Auto Updates: Enabled (no auto reboot)"
echo "Fail2Ban: Active"
echo "UV Project: $WORKDIR/uv_project"
echo "Jupyter Port: 5000"
echo ""
echo -e "${GREEN}To connect locally:${NC}"
echo "ssh -N -L localhost:5000:localhost:5000 root@<your-server-ip>"
echo "Then open: http://localhost:5000/?token=$TOKEN"
echo ""
echo -e "${GREEN}To view Jupyter logs:${NC}"
echo "tmux attach -t jupyter"
echo "Press Ctrl+B, then D to detach"
echo ""
