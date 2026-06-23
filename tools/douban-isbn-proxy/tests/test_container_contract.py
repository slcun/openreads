import subprocess
import time
from pathlib import Path

import httpx
import pytest

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parent


def _docker_available() -> bool:
    try:
        subprocess.run(
            ["docker", "info"],
            capture_output=True,
            check=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


@pytest.fixture(scope="session")
def docker_image():
    tag = "douban-isbn-proxy:test"
    subprocess.run(
        ["docker", "build", "-t", tag, "."],
        cwd=str(PROJECT_ROOT),
        check=True,
        capture_output=True,
    )
    return tag


@pytest.mark.skipif(not _docker_available(), reason="Docker not available")
def test_container_exposes_health_route(tmp_path, docker_image):
    tag = docker_image
    container_id = None
    try:
        result = subprocess.run(
            [
                "docker", "run", "--rm", "-d",
                "-p", "127.0.0.1:18080:8080",
                "-v", f"{tmp_path}:/data",
                "-e", "BIND_PORT=8080",
                "-e", "CACHE_PATH=/data/cache.sqlite3",
                tag,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        container_id = result.stdout.strip()
        time.sleep(2)
        response = httpx.get("http://127.0.0.1:18080/healthz", timeout=5)
        assert response.status_code == 204
    finally:
        if container_id:
            subprocess.run(["docker", "stop", container_id], capture_output=True)
