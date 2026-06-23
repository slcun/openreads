"""Tests for deployment-time runtime dependencies."""

import tomllib
from pathlib import Path


def test_runtime_dependencies_include_httpx_brotli_support():
    pyproject_path = Path(__file__).parents[1] / "pyproject.toml"
    project = tomllib.loads(pyproject_path.read_text(encoding="utf-8"))["project"]

    assert "httpx[brotli]>=0.28,<1" in project["dependencies"]


def test_setuptools_packages_exclude_runtime_cache_directories():
    pyproject_path = Path(__file__).parents[1] / "pyproject.toml"
    project = tomllib.loads(pyproject_path.read_text(encoding="utf-8"))

    assert project["tool"]["setuptools"]["packages"] == ["douban_isbn_proxy"]
