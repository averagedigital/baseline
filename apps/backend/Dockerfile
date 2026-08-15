FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY pyproject.toml alembic.ini ./
COPY migrations ./migrations
COPY baseline_backend ./baseline_backend
RUN pip install --no-cache-dir .
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn baseline_backend.main:app --host 0.0.0.0 --port 8000"]
