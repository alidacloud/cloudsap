FROM ruby:2.7 as build

# Bundler settings live in the environment (not /root/.bundle/config) so the
# non-root runtime user can read them
ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=vendor \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_NO_CACHE=true \
    BUNDLE_JOBS=5

RUN mkdir /app

WORKDIR /app

COPY lib/ ./lib
COPY bin/ ./bin
COPY exe/ ./exe
COPY *.md *.rdoc *.gemspec Gemfile* LICENSE.txt ./

RUN echo 'gem: --no-document' > /etc/gemrc \
  && bundle install -j4 --retry 3 \
  && gem source --clear-all

#####################################################################
# Ready to Publish
#####################################################################

FROM ruby:2.7-slim
LABEL maintainer="Brian Warsing <dayglojesus@gmail.com>"

ARG APP_UID=10001
ARG APP_GID=10001

ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=vendor \
    BUNDLE_WITHOUT="development:test" \
    HOME=/home/cloudsap

RUN groupadd --gid ${APP_GID} cloudsap \
  && useradd --uid ${APP_UID} --gid ${APP_GID} --home-dir /home/cloudsap \
     --create-home --shell /usr/sbin/nologin cloudsap

# App files are owned by root and read-only to the runtime user
COPY --from=build /app /app

WORKDIR /app

# Numeric UID so Kubernetes can verify runAsNonRoot
USER ${APP_UID}:${APP_GID}

ENTRYPOINT ["bundle", "exec", "cloudsap"]
