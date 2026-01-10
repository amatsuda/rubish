# Dockerfile for running rubish tests in a clean environment
# This avoids loading developer's local rc files during tests

FROM ruby:4.0-slim

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
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
COPY Gemfile Gemfile.lock* ./

# Install dependencies
RUN bundle install

# Copy the rest of the application
COPY . .

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
