# Dockerfile for running rubish tests in a clean environment
# This avoids loading developer's local rc files during tests

ARG RUBY_VERSION=4.0
FROM ruby:${RUBY_VERSION}-slim

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Verify Ruby version
RUN ruby -v

# Create a test user with a clean home directory and multiple groups
RUN groupadd testgroup1 && \
    groupadd testgroup2 && \
    useradd -m -s /bin/bash -G testgroup1,testgroup2 testuser

# Set working directory
WORKDIR /app

# Copy Gemfile first for layer caching
COPY Gemfile *.gemspec ./
COPY lib/rubish/version.rb lib/rubish/version.rb

# Install a compatible bundler version, then install dependencies
RUN gem install bundler --no-document 2>/dev/null || gem install bundler -v 2.4.22 --no-document
RUN bundle install

# Copy the rest of the application (remove host lockfile so the one generated above is used)
COPY . .
RUN rm -f Gemfile.lock && bundle install

# Ensure clean home directory (no rc files)
RUN rm -f /home/testuser/.bashrc \
          /home/testuser/.bash_profile \
          /home/testuser/.profile \
          /home/testuser/.bash_logout \
          /root/.bashrc \
          /root/.bash_profile \
          /root/.profile \
    && mkdir -p /home/testuser \
    && chown -R testuser:testuser /home/testuser /app

# Switch to test user
USER testuser
ENV HOME=/home/testuser

# Ensure no rc files exist (don't set XDG_CONFIG_HOME - let tests control it)
RUN rm -rf /home/testuser/.config/rubish \
           /home/testuser/.rubishrc \
           /home/testuser/.rubish_profile \
           /home/testuser/.rubish_logout

# Run tests
CMD ["bundle", "exec", "rake", "test"]
