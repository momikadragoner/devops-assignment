###############################################################################
# Dockerfile — Custom Gitea image for the ELTE DevOps assignment
#
# Extends the official Gitea image and bakes in organizational defaults.
# These defaults are set via ENV so they can still be overridden at runtime
# by the App Service "app_settings" environment variables.
#
# Build:  docker build -t gitea-custom .
# Run:    docker run -p 3000:3000 gitea-custom
###############################################################################

ARG GITEA_VERSION=1.22
FROM gitea/gitea:${GITEA_VERSION}

LABEL maintainer="elte-devops-assignment" \
      org.opencontainers.image.title="Gitea (ELTE DevOps)" \
      org.opencontainers.image.description="Custom Gitea build with org defaults baked in"

# ---------------------------------------------------------------------------
# Bake in organisational defaults.
# Values here are overridden by Azure App Service "app_settings" at runtime
# (GITEA__section__key environment variables).
# ---------------------------------------------------------------------------
ENV GITEA__server__APP_NAME="ELTE DevOps Gitea" \
    GITEA__ui__DEFAULT_THEME="gitea-auto" \
    GITEA__service__DISABLE_REGISTRATION="false" \
    GITEA__service__REQUIRE_SIGNIN_VIEW="false" \
    GITEA__log__LEVEL="Info"

# Copy the custom Gitea welcome page template (shown on the explore/home page)
COPY custom/templates/home.tmpl /data/gitea/templates/home.tmpl

# Gitea HTTP port
EXPOSE 3000
# Gitea SSH port (not used on App Service, but kept for local docker run)
EXPOSE 22

# Entrypoint is inherited from the base image
