# Two stages. The first only reads .git to record which commit is being built,
# which is why the build context is the repository root. /healthz reports it.
FROM alpine/git:latest AS version
WORKDIR /repo
COPY .git .git
RUN git log -1 --format=%h > /VERSION \
 && git log -1 --format=%cI >> /VERSION \
 || (echo dev > /VERSION && echo "" >> /VERSION)

FROM python:3.12-slim
WORKDIR /app

COPY src/python/relay/pyproject.toml ./
COPY src/python/relay/relay ./relay

# INSTALL_DEV=1 adds pytest, for the tests profile only. The image that runs on
# the server carries nothing it does not need.
ARG INSTALL_DEV=0
RUN if [ "$INSTALL_DEV" = "1" ]; then pip install --no-cache-dir ".[dev]"; \
    else pip install --no-cache-dir .; fi

COPY src/python/relay/tests ./tests
COPY --from=version /VERSION /app/VERSION

# The relay runs as an unprivileged user; it needs no write access.
RUN useradd --system --no-create-home relay
USER relay

EXPOSE 8000

# One worker: the routing table and the open streams live in this process.
CMD ["uvicorn", "relay.main:app", "--factory", "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]
