#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

WORKDIR="/root/uv_project/uv_project"
SESSION="jupyter"
PORT=5000

if pgrep -f "jupyter.notebook.*--port $PORT" >/dev/null 2>&1; then
  TOKEN=$(grep -o 'token=[a-z0-9]*' "$WORKDIR/jupyter.log" | tail -1 | cut -d'=' -f2)
  echo -e "${GREEN}Jupyter is already running on port $PORT.${NC}"
  echo "SSH tunnel: ssh -N -L localhost:$PORT:localhost:$PORT root@<your-server-ip>"
  echo "Access:     http://localhost:$PORT/?token=$TOKEN"
  echo "Attach:     tmux attach -t $SESSION"
  exit 0
fi

echo -e "${RED}Jupyter is not running. Relaunching...${NC}"
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" "cd $WORKDIR && source .venv/bin/activate && jupyter notebook --port $PORT --no-browser --allow-root 2>&1 | tee jupyter.log"

sleep 5
TOKEN=$(grep -o 'token=[a-z0-9]*' "$WORKDIR/jupyter.log" | tail -1 | cut -d'=' -f2)

echo -e "${GREEN}Jupyter restarted in tmux session '$SESSION'.${NC}"
echo "SSH tunnel: ssh -N -L localhost:$PORT:localhost:$PORT root@<your-server-ip>"
echo "Access:     http://localhost:$PORT/?token=$TOKEN"
echo "Attach:     tmux attach -t $SESSION"
