#!/usr/bin/env bash
set -e
fail() { echo "❌ $1" >&2; exit 1; }

# --- Root and environment checks ---
if [[ $(id -u) -ne 0 ]]; then
  fail "Run as root (use: sudo $0)"
fi
if grep -qi Microsoft /proc/version; then
  fail "Running inside WSL is not supported"
fi

# --- SSH port selection ---
DEFAULT_SSH_PORT=22
read -e -p "Enter SSH port [default: 22, e.g. 2222 for obscurity]: " SSH_PORT
SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}

# --- SSH key setup (for the current sudo user) ---
SUDO_HOME=$(eval echo "~$SUDO_USER")
mkdir -p "$SUDO_HOME/.ssh"
chmod 700 "$SUDO_HOME/.ssh"
if [[ ! -s "$SUDO_HOME/.ssh/authorized_keys" ]]; then
  read -e -p "Paste your public SSH key: " PUBKEY
  echo "$PUBKEY" > "$SUDO_HOME/.ssh/authorized_keys"
  chmod 600 "$SUDO_HOME/.ssh/authorized_keys"
  chown -R "$SUDO_USER:$SUDO_USER" "$SUDO_HOME/.ssh"
fi

# --- SSH client defaults ---
cat << 'EOF' > "$SUDO_HOME/.ssh/config"
Host *
  ServerAliveInterval 60
  StrictHostKeyChecking no
EOF
chmod 600 "$SUDO_HOME/.ssh/config"
chown "$SUDO_USER:$SUDO_USER" "$SUDO_HOME/.ssh/config"

# --- System updates + core packages ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -qy
apt-get upgrade -qy
apt-get install -qy vim nano tmux curl git htop ufw fail2ban unattended-upgrades python3-pip

# --- Install uv (Python package manager) ---
curl -LsSf https://astral.sh/uv/install.sh | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SUDO_HOME/.bashrc"
chown "$SUDO_USER:$SUDO_USER" "$SUDO_HOME/.bashrc"

# --- Enable unattended upgrades (no auto reboot) ---
cat << 'EOF' > /etc/apt/apt.conf.d/51unattended-upgrades-local
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable unattended-upgrades

# --- Harden SSH configuration ---
SSH_CONFIG="/etc/ssh/sshd_config"
perl -ni.bak -e 'print unless /^\s*(PermitEmptyPasswords|PermitRootLogin|PasswordAuthentication|ChallengeResponseAuthentication|Port)/' "$SSH_CONFIG"

cat << EOF >> "$SSH_CONFIG"
Port $SSH_PORT
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
PermitRootLogin no
EOF

systemctl reload ssh || systemctl restart ssh

# --- Firewall setup ---
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp comment 'SSH access'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 5000/tcp comment 'Jupyter Notebook'
ufw limit $SSH_PORT/tcp comment 'Rate-limit SSH brute-force'
ufw --force enable

# --- Fail2Ban configuration ---
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

echo "✅ System secured and hardened:"
echo "   • SSH key-only login on port $SSH_PORT"
echo "   • Root login disabled"
echo "   • Auto security updates (no automatic reboot)"
echo "   • Fail2Ban active + UFW rate-limiting"
echo "   • Firewall allows: SSH($SSH_PORT), HTTP(80), HTTPS(443), Jupyter(5000)"
echo "   • Installed tools: vim, nano, tmux, git, htop, uv"
echo "🔒 Verify SSH before disconnecting:"
echo "   ssh -p $SSH_PORT $SUDO_USER@<your-server-ip>"
