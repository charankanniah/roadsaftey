#!/usr/bin/env python3
"""
PotholeGuard - One-click launcher
Starts:
  1. FastAPI backend on http://localhost:8000
  2. Static file server for dashboard on http://localhost:3000
  3. Opens browser to the control hub

Usage:
    py start.py
"""

import sys
import os
import time
import threading
import subprocess
import webbrowser
import http.server
import socketserver

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
BACKEND_DIR = os.path.join(PROJECT_ROOT, "backend")


def start_backend():
    """Launch FastAPI backend with uvicorn."""
    env = os.environ.copy()
    env["PYTHONPATH"] = BACKEND_DIR + os.pathsep + env.get("PYTHONPATH", "")
    cmd = [sys.executable, "-m", "uvicorn", "app.main:app",
           "--host", "0.0.0.0", "--port", "8000", "--reload"]
    print("[PotholeGuard] Starting FastAPI backend on http://localhost:8000 ...")
    proc = subprocess.Popen(cmd, cwd=BACKEND_DIR, env=env)
    return proc


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Static file handler that suppresses per-request logging."""
    def log_message(self, format, *args):
        pass


def start_static_server(port=3000):
    """Serve the project root as a static HTTP site."""
    os.chdir(PROJECT_ROOT)
    try:
        httpd = socketserver.TCPServer(("", port), QuietHandler)
        print("[PotholeGuard] Static server on http://localhost:{0}".format(port))
        httpd.serve_forever()
    except OSError as e:
        print("[PotholeGuard] Port {0} busy ({1}). Static server skipped.".format(port, e))


def open_browser():
    """Open the control hub after a brief startup delay."""
    time.sleep(2.5)
    url = "http://localhost:3000/index.html"
    print("[PotholeGuard] Opening browser: {0}".format(url))
    webbrowser.open(url)


if __name__ == "__main__":
    print("=" * 60)
    print("  PotholeGuard - Starting all services")
    print("=" * 60)

    backend_proc = start_backend()

    t_static = threading.Thread(target=start_static_server, daemon=True)
    t_static.start()

    t_browser = threading.Thread(target=open_browser, daemon=True)
    t_browser.start()

    print()
    print("  Backend API :  http://localhost:8000")
    print("  API Docs    :  http://localhost:8000/docs")
    print("  Dashboard   :  http://localhost:3000/dashboard/index.html")
    print("  Control Hub :  http://localhost:3000/index.html")
    print()
    print("  Press Ctrl+C to stop all services.")
    print("=" * 60)

    try:
        backend_proc.wait()
    except KeyboardInterrupt:
        print("\n[PotholeGuard] Shutting down...")
        backend_proc.terminate()
        sys.exit(0)
