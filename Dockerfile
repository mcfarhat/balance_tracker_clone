# syntax=docker/dockerfile:1.5
ARG PAAS_PSQL_VERSION=11251948d5dd4867552f9b9836a9e02110304df5
FROM ghcr.io/alphagov/paas/psql:${PAAS_PSQL_VERSION} AS psql_client

RUN <<EOF
  set -e
  apk add --no-cache bash
  adduser -s /bin/bash -G users -D "haf_admin"
EOF

USER haf_admin
WORKDIR /home/haf_admin

ENTRYPOINT [ "/bin/bash", "-c" ]

FROM psql_client AS full

ARG BUILD_TIME
ARG GIT_COMMIT_SHA
ARG GIT_CURRENT_BRANCH
ARG GIT_LAST_LOG_MESSAGE
ARG GIT_LAST_COMMITTER
ARG GIT_LAST_COMMIT_DATE
LABEL org.opencontainers.image.created="$BUILD_TIME"
LABEL org.opencontainers.image.url="https://hive.io/"
LABEL org.opencontainers.image.documentation="https://gitlab.syncad.com/hive/balance_tracker"
LABEL org.opencontainers.image.source="https://gitlab.syncad.com/hive/balance_tracker"
#LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="$GIT_COMMIT_SHA"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.ref.name="Balance Tracker"
LABEL org.opencontainers.image.title="Balance Tracker Image"
LABEL org.opencontainers.image.description="Runs Balance Tracker application"
LABEL io.hive.image.branch="$GIT_CURRENT_BRANCH"
LABEL io.hive.image.commit.log_message="$GIT_LAST_LOG_MESSAGE"
LABEL io.hive.image.commit.author="$GIT_LAST_COMMITTER"
LABEL io.hive.image.commit.date="$GIT_LAST_COMMIT_DATE"

USER root

RUN <<EOF
  set -e
  mkdir /app
  chown haf_admin /app
EOF

USER haf_admin

COPY scripts/install_app.sh /app/scripts/install_app.sh
COPY scripts/uninstall_app.sh /app/scripts/uninstall_app.sh
COPY db /app/db
COPY api /app/api
COPY endpoints /app/endpoints
COPY dump_accounts /app/dump_accounts
COPY balance-tracker.sh /app/balance-tracker.sh
COPY docker/scripts/block-processing-healthcheck.sh /app/block-processing-healthcheck.sh
COPY docker/scripts/docker-entrypoint.sh /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]