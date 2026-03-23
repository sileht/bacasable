FROM python:3.15-slim-bookworm
RUN apt-get update && apt-get install -y \
    build-essential gcc \
    libssl-dev \
    libffi-dev \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*



RUN peotry sync --only main


WORKDIR /opt/app
ENTRYPOINT ["poetry", "run"]
CMD ["server"]
