FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# renovate: datasource=custom depName=funkwhale
ARG FUNKWHALE_VERSION=2.0.0-rc13

RUN mkdir -p /app/code /app/pkg

WORKDIR /app/code

# System dependencies (from Funkwhale's Dockerfile.debian)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libldap2-dev \
    libsasl2-dev \
    libmagic1 \
    libpq-dev \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Download and extract Funkwhale API + Frontend
RUN curl -L -o /tmp/api.zip \
      "https://dev.funkwhale.audio/funkwhale/funkwhale/-/jobs/artifacts/${FUNKWHALE_VERSION}/download?job=build_api" \
    && curl -L -o /tmp/front.zip \
      "https://dev.funkwhale.audio/funkwhale/funkwhale/-/jobs/artifacts/${FUNKWHALE_VERSION}/download?job=build_front" \
    && unzip /tmp/api.zip -d /app/code/ \
    && unzip /tmp/front.zip -d /app/code/ \
    && rm /tmp/api.zip /tmp/front.zip

# Create Python venv and install Funkwhale
RUN python3 -m venv /app/code/venv \
    && /app/code/venv/bin/pip install --upgrade pip wheel \
    && /app/code/venv/bin/pip install --editable /app/code/api

# Copy package files
COPY start.sh nginx.conf /app/pkg/

CMD ["/app/pkg/start.sh"]
