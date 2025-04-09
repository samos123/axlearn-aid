#!/usr/bin/env bash
set -x

gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -n 1 || echo 0)

# Check if uv is installed
if ! command -v uv &> /dev/null; then
  echo "uv could not be found, installing..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # Add uv to PATH for this script's execution
  export PATH="$HOME/.local/bin:$PATH"
else
  echo "uv is already installed."
fi

# Clone the repository if it doesn't exist
if [ ! -d "axlearn" ]; then
  echo "Cloning axlearn repository..."
  git clone https://github.com/apple/axlearn.git
else
  echo "axlearn directory already exists, skipping clone."
fi
cd axlearn

# Create venv and install dependencies using uv
echo "Creating virtual environment..."
uv venv
echo "Activating virtual environment..."
source .venv/bin/activate

echo "Installing base dependencies..."
uv pip install '.[core]'

# Check GPU count and run appropriate tests
if [ "$gpu_count" -ge 1 ]; then
  echo "GPU detected ($gpu_count). Installing GPU dependencies and running parallel tests..."
  uv pip install '.[gpu]' # Install GPU specific dependencies
  uv pip install --upgrade --force-reinstall 'jax[cuda12]==0.5.3'
  # Run tests in parallel using the number of GPUs
  # pytest -n "$gpu_count" axlearn/common/flash_attention/gpu_attention_test.py
  pytest axlearn/common/flash_attention/gpu_attention_test.py
else
  echo "No GPU detected. Running standard tests..."
  # Run standard tests (adjust command as needed if different from GPU tests)
  pytest axlearn
fi

echo "Deactivating virtual environment..."
deactivate

echo "Script finished."
