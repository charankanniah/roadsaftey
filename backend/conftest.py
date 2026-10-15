"""
conftest.py — makes `app` importable when pytest runs from any working directory.
Inserts the backend/ directory at the front of sys.path so that
`from app.main import app` resolves correctly.
"""
import sys
import os

# Ensure backend/ is always on sys.path regardless of CWD
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
