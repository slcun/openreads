FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY douban_isbn_proxy ./douban_isbn_proxy
RUN pip install --no-cache-dir .
ENV BIND_PORT=8080
ENV DOUBAN_PROXY_CACHE_PATH=/data/cache.sqlite3
EXPOSE 8080
CMD ["python", "-m", "douban_isbn_proxy"]
