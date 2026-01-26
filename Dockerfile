ARG DEBIAN_FRONTEND=noninteractive
ARG PG_MAJOR=18
ARG POSTGIS_MAJOR=3
ARG PGDG_CODENAME=bookworm

FROM debian:bookworm-slim AS postgres-base

# Re-declare build args used in this stage
ARG DEBIAN_FRONTEND
ARG PG_MAJOR
ARG PGDG_CODENAME

# Small set of tools + add PGDG apt repository and key (using gpg dearmor)
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget gnupg dirmngr lsb-release apt-transport-https \
    && mkdir -p /usr/share/keyrings; \
    wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor --yes -o /usr/share/keyrings/pgdg.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt/ ${PGDG_CODENAME}-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list; \
    rm -rf /var/lib/apt/lists/*

# Install gosu
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends gosu \
    && rm -rf /var/lib/apt/lists/*

# Install base Postgres packages
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends \
      "postgresql-${PG_MAJOR}" \
      "postgresql-client-${PG_MAJOR}" \
      "postgresql-contrib" \
    && rm -rf /var/lib/apt/lists/*

FROM postgres-base AS postgis-stage

ARG DEBIAN_FRONTEND
ARG PG_MAJOR
ARG POSTGIS_MAJOR

# Install PostGIS packages (this layer changes when POSTGIS_MAJOR / postgis package changes)
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends \
      postgis \
      "postgresql-${PG_MAJOR}-postgis-${POSTGIS_MAJOR}" \
    && rm -rf /var/lib/apt/lists/*


FROM postgis-stage AS trigram-stage

ARG DEBIAN_FRONTEND
ARG PG_MAJOR

# Install PostgreSQL trigram extension (pg_trgm) from contrib
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends \
      "postgresql-${PG_MAJOR}-contrib" \
    && rm -rf /var/lib/apt/lists/*

FROM trigram-stage AS hoshina-pg

ARG PG_MAJOR
ARG POSTGIS_MAJOR

# Copy official entrypoint so behaviour matches upstream postgres image
RUN set -eux; \
    wget -O /usr/local/bin/docker-entrypoint.sh \
      https://raw.githubusercontent.com/docker-library/postgres/master/docker-entrypoint.sh; \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Create directory for initialization scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Create postgres user if it doesn't exist (needed by entrypoint script)
RUN set -eux; \
    if ! id postgres > /dev/null 2>&1; then \
      useradd -m -d /var/lib/postgresql -s /bin/bash postgres; \
    fi; \
    mkdir -p /var/lib/postgresql/data; \
    chown -R postgres:postgres /var/lib/postgresql /docker-entrypoint-initdb.d

# Set PATH to include PostgreSQL binaries
ENV PATH=/usr/lib/postgresql/$PG_MAJOR/bin:$PATH \
    PGDATA=/var/lib/postgresql/data
VOLUME ["/var/lib/postgresql/data"]
EXPOSE 5432

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres", "-c", "listen_addresses=*"]
