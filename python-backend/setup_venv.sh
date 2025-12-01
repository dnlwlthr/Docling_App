#!/bin/bash
# Setup script to create virtual environment and install dependencies
# Run this before bundling the backend into the macOS app

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "Creating virtual environment..."
python3 -m venv venv

echo "Activating virtual environment..."
source venv/bin/activate

echo "Upgrading pip..."
pip install --upgrade pip

echo "Installing dependencies..."
pip install -r requirements.txt

echo "Setup complete!"
echo ""
echo "To test the backend manually, run:"
echo "  source venv/bin/activate"
echo "  uvicorn main:app --host 127.0.0.1 --port 8765"

