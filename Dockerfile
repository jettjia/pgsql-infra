# Use pgvector/pgvector:pg16 as the base image which already has pgvector installed
FROM pgvector/pgvector:pg16

# Set DEBIAN_FRONTEND to noninteractive to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Arguments
ARG PG_MAJOR=16

# 1. Switch main Debian/Ubuntu APT sources to a Chinese mirror (Aliyun)
#    and PGDG sources to Tsinghua mirror for potentially faster downloads.
RUN \
  echo "INFO: Attempting to switch main Debian APT sources to mirrors.aliyun.com..." && \
  if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
    echo "INFO: Modifying /etc/apt/sources.list.d/debian.sources" && \
    sed -i 's|http://deb.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's|http://security.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources; \
  elif [ -f /etc/apt/sources.list ]; then \
    echo "INFO: Modifying /etc/apt/sources.list" && \
    sed -i 's|http://deb.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list && \
    sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list; \
  else \
    echo "WARNING: Standard Debian/Ubuntu APT source files not found in expected locations."; \
  fi 

# 添加PGDG源并设置优先级，确保使用一致的版本
RUN echo "INFO: Configuring PGDG APT source with Tsinghua mirror..." && \
  echo "deb http://mirrors.tuna.tsinghua.edu.cn/postgresql/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
  # 添加PGDG签名密钥
  (gpg --keyserver keyserver.ubuntu.com --recv-keys 7FCC7D46ACCC4CF8 || \
   gpg --keyserver pgp.mit.edu --recv-keys 7FCC7D46ACCC4CF8 || \
   gpg --keyserver keyserver.pgp.com --recv-keys 7FCC7D46ACCC4CF8) && \
  gpg --export 7FCC7D46ACCC4CF8 | apt-key add - && \
  find /etc/apt/sources.list* -type f -name '*.list' -exec \
    sed -i 's|http://apt.postgresql.org/pub/repos/apt|http://mirrors.tuna.tsinghua.edu.cn/postgresql/repos/apt|g' {} + || \
  echo "WARNING: PGDG APT source replacement did not find a typical pgdg.list or encountered an error. Proceeding..."

# 2. Install build dependencies for pg_jieba
RUN apt-get update && \
    # 先安装特定版本的libpq5以解决依赖冲突，允许降级
    apt-get install -y --no-install-recommends --allow-downgrades libpq5=17.5-1.pgdg120+1 && \
    # 然后安装其他依赖包
    apt-get install -y --no-install-recommends \
    build-essential \
    unzip \
    procps \
    cmake \
    postgresql-server-dev-${PG_MAJOR} && \
    rm -rf /var/lib/apt/lists/*

# 3. Copy pg_jieba from local source
COPY pg_jieba/ /tmp/pg_jieba

# 4. Fix directory structure for limonp
RUN mkdir -p /tmp/pg_jieba/libjieba/deps && \
    # Move limonp to deps directory if it exists in the wrong location
    if [ -d "/tmp/pg_jieba/libjieba/limonp" ]; then \
      mv /tmp/pg_jieba/libjieba/limonp /tmp/pg_jieba/libjieba/deps/; \
    fi && \
    # Ensure include directories are available to compiler
    ln -sf /tmp/pg_jieba/libjieba/deps/limonp/include/limonp /usr/include/limonp

# 5. Create build directory and compile pg_jieba
RUN cd /tmp/pg_jieba && mkdir -p build && cd build && \
    cmake -DPostgreSQL_LIBRARY=/usr/lib/postgresql/${PG_MAJOR}/bin \
          -DPostgreSQL_INCLUDE_DIR=/usr/include/postgresql/${PG_MAJOR} \
          -DPostgreSQL_TYPE_INCLUDE_DIR=/usr/include/postgresql/${PG_MAJOR}/server \
          .. && \
    make && make install

# 6. Clean up pg_jieba sources
RUN rm -rf /tmp/pg_jieba

# 7. Install Apache AGE (Graph Extension)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    unzip \
    libreadline-dev \
    zlib1g-dev \
    flex \
    bison \
    libxml2-dev \
    libxslt1-dev \
    libssl-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy and install AGE from local zip file instead of git clone
COPY age-master.zip /tmp/age-master.zip
RUN unzip /tmp/age-master.zip -d /tmp && \
    cd /tmp/age-master && \
    make PG_CONFIG=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config && \
    make PG_CONFIG=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config install && \
    rm -rf /tmp/age-master /tmp/age-master.zip

# 8. Modify PostgreSQL configuration to load pg_jieba and AGE
# Note: pgvector is already configured in the pgvector/pgvector base image
RUN echo "shared_preload_libraries = 'pg_jieba.so,vector.so,age.so'" >> /usr/share/postgresql/${PG_MAJOR}/postgresql.conf.sample

# 9. Clean up build dependencies
RUN apt-get update && \
    apt-get purge -y build-essential unzip cmake && \
    apt-get purge -y postgresql-server-dev-${PG_MAJOR} && \
    apt-get autoremove -y --purge && \
    rm -rf /var/lib/apt/lists/*

# The base image pgvector/pgvector should already have a CMD/ENTRYPOINT for PostgreSQL.