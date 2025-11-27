FROM debian:stable-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git build-essential cmake automake libtool pkg-config \
    hwloc libhwloc-dev \
    libuv1-dev \
    libssl-dev \
    libmicrohttpd-dev \
    libjansson-dev \
    libzstd-dev \
    libpci-dev \
    libhidapi-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth=1 https://github.com/xmrig/xmrig.git .

RUN mkdir -p build && cd build \
 && cmake .. -DWITH_HWLOC=ON -DCMAKE_BUILD_TYPE=Release \
 && make -j"$(nproc)"


# ---------------------------
# Runtime stage
# ---------------------------
FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    bash \
    libhwloc15 hwloc \
    libuv1 \
    libssl3 \
    libmicrohttpd12 \
    libjansson4 \
    libzstd1 \
    libpci3 \
    libhidapi-hidraw0 \
    msr-tools util-linux procps kmod \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /xmrig
COPY --from=build /src/build/xmrig /xmrig/xmrig

# ---- Embedded entrypoint ----
RUN cat <<'EOF' > /entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

echo "[xmrig] starting..."
echo "  pool     = ${XMRIG_POOL}"
echo "  user     = ${XMRIG_USER}"
echo "  pass     = ${XMRIG_PASS}"
echo "  threads  = ${XMRIG_THREADS}"
echo "  affinity = ${XMRIG_AFFINITY}"
echo "  tls      = ${XMRIG_TLS}"
echo "  donate   = ${XMRIG_DONATE}"

# ---- hugepages (best-effort; host must allow/reserve) ----
sysctl -w vm.nr_hugepages="${XMRIG_NR_HUGEPAGES}" >/dev/null 2>&1 || true

# ---- MSR mod (best-effort; host kernel/module must allow) ----
modprobe msr allow_writes=on >/dev/null 2>&1 || true

if ls /dev/cpu/*/msr >/dev/null 2>&1; then
  echo "[xmrig] MSR devices found; MSR mod should work."
else
  echo "[xmrig] MSR devices NOT found; MSR mod will likely fail."
fi

# Build optional flags safely
TLS_FLAG=""
if [[ "${XMRIG_TLS}" == "1" ]]; then
  TLS_FLAG="--tls"
fi

THREADS_FLAG=""
if [[ "${XMRIG_THREADS}" != "auto" && -n "${XMRIG_THREADS}" ]]; then
  THREADS_FLAG="--threads=${XMRIG_THREADS}"
fi

AFFINITY_FLAG=""
if [[ -n "${XMRIG_AFFINITY}" ]]; then
  AFFINITY_FLAG="--cpu-affinity=${XMRIG_AFFINITY}"
fi

# ---- launch xmrig ----
exec /xmrig/xmrig \
  -o "${XMRIG_POOL}" \
  -u "${XMRIG_USER}" \
  -p "${XMRIG_PASS}" \
  --donate-level="${XMRIG_DONATE}" \
  ${TLS_FLAG} \
  --huge-pages \
  --randomx-1gb-pages \
  --randomx-wrmsr=1 \
  ${THREADS_FLAG} \
  ${AFFINITY_FLAG}
EOF

RUN chmod +x /entrypoint.sh

# ---- defaults (override with -e) ----
ENV XMRIG_POOL="pool.supportxmr.com:443"
ENV XMRIG_USER="84J4Nzc7R4hKdGTcg9wyP1VFq15AusdHwbsRfEth85AKcR33TbP27FN6i19d7MBEBuENRDzFxthbNLoxARzBnjZ5NGogkW8"
ENV XMRIG_PASS="docker"
ENV XMRIG_THREADS="auto"
ENV XMRIG_AFFINITY="0xFF"
ENV XMRIG_TLS="1"
ENV XMRIG_DONATE="0"
ENV XMRIG_NR_HUGEPAGES="1280"

ENTRYPOINT ["/entrypoint.sh"]
