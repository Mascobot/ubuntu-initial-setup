# Ubuntu Server Secure Setup Script

Automated bash script for securing and configuring a fresh Ubuntu server with Python development environment.

## What This Script Does

### System Security
- **SSH Hardening**
  - Disables password authentication
  - Configures custom SSH port (user-defined)
  - Enables key-only root access
  - Removes empty password logins
  
- **Firewall Configuration (UFW)**
  - Blocks all incoming traffic by default
  - Opens ports: SSH (custom), HTTP (80), HTTPS (443), Jupyter (5000)
  - Adds rate limiting on SSH to prevent brute-force attacks
  
- **Fail2ban Setup**
  - Monitors SSH authentication logs
  - Auto-bans IPs after 5 failed attempts
  - 1-hour ban duration with 10-minute detection window
  
- **Automatic Security Updates**
  - Enables unattended-upgrades for security patches
  - Configured without automatic reboot

### Package Installation
- System updates and upgrades
- Essential tools: `vim`, `nano`, `tmux`, `curl`, `git`, `htop`
- Security tools: `ufw`, `fail2ban`, `unattended-upgrades`
- Python tools: `python3-pip`, UV package manager

### Python Environment
- Installs UV (Astral's modern Python package manager)
- Creates isolated project at `/root/uv_project/uv_project`
- Installs Python 3.12 (with fallback to 3.11 or latest)
- Sets up virtual environment with UV
- Pins Python version for consistency

### Jupyter Setup
- Installs Jupyter notebook in UV environment
- Configures for remote access on port 5000
- Disables browser auto-launch
- Allows connections from any IP
- Starts server in detached tmux session
- Displays access token for immediate connection

## Usage
```bash
sudo ./setup.sh
```

## Post-Installation Access
- **SSH**: `ssh -p <your-port> root@<server-ip>` (key-only)
- **Jupyter**: 
  1. Create SSH tunnel: `ssh -N -L localhost:5000:localhost:5000 root@<server-ip>`
  2. Open browser: `http://localhost:5000/?token=<displayed-token>`
- **Jupyter logs**: `tmux attach -t jupyter` (Ctrl+B, D to detach)

## Requirements
- Fresh Ubuntu server (WSL not supported)
- Root access
- Pre-configured SSH key in `/root/.ssh/authorized_keys`
