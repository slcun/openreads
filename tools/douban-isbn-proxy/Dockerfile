FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY douban_isbn_proxy ./douban_isbn_proxy
RUN pip install --no-cache-dir .
ENV BIND_PORT=8080
ENV DOUBAN_PROXY_CACHE_PATH=/data/cache.sqlite3
ENV COVER_CACHE_PATH=/data/covers
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')"
CMD ["python", "-m", "douban_isbn_proxy"]
