FROM python:3.14-slim-bookworm
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*



RUN peotry sync --only main


WORKDIR /app
ENTRYPOINT ["poetry", "run"]
CMD ["worker"]
