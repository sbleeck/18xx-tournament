FROM ruby:3.4

ARG RACK_ENV
ARG JOBS=1
ARG MAKEFLAGS=-j1
ENV JOBS=${JOBS}
ENV MAKEFLAGS=${MAKEFLAGS}

RUN mkdir /18xx
WORKDIR /18xx
RUN git config --global --add safe.directory /18xx

# --- START FIX ---
# Force an absolute single-threaded build by intercepting gyp make calls and dropping downstream -j flags
RUN echo '#!/usr/bin/env ruby' > /usr/local/bin/make && \
    echo 'args = ARGV.reject { |a| a.start_with?("-j") }' >> /usr/local/bin/make && \
    echo 'exec("/usr/bin/make", "-j1", *args)' >> /usr/local/bin/make && \
    chmod +x /usr/local/bin/make
# --- END FIX ---

RUN if [ "$RACK_ENV" = "development" ]; \
    then \
      ARCH=$(uname -m); \
      if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        curl -s https://registry.npmjs.org/esbuild-linux-arm64/-/esbuild-linux-arm64-0.14.36.tgz | tar xz; \
      else \
        curl -s https://registry.npmjs.org/esbuild-linux-64/-/esbuild-linux-64-0.14.36.tgz | tar xz; \
      fi; \
      mv package/bin/esbuild /usr/local/bin && rm -rf package; \
    fi;

COPY Gemfile Gemfile.lock ./
RUN if [ "$RACK_ENV" = "production" ]; \
    then bundle config set without 'test development'; \
    fi; \
    bundle install;
COPY . .

CMD bundle exec rake dev_up && \
    bundle exec rerun --background -i 'build/*' -i 'public/*' 'unicorn -c config/unicorn.rb'