# Local services

FlowBrigade does not start Redis or Memcached for you. Integration tests use
local services only when they are already running, and print `SKIP:` with the
reason when a service is unavailable.

This document only covers what is needed to verify FlowBrigade adapters. Service
configuration, persistence, networking, authentication, and production hardening
belong to each service's own documentation.

## Redis

For one-off verification without enabling a system service, start Redis on a
temporary port:

```sh
redis-server --port 6380 --bind 127.0.0.1 --save '' --appendonly no --daemonize yes --pidfile /tmp/flowbrigade-redis.pid --dir /tmp
FLOWBRIGADE_REDIS_HOST=127.0.0.1 FLOWBRIGADE_REDIS_PORT=6380 nim r -p:packages/flowbrigade_redis/src -p:src packages/flowbrigade_redis/tests/test_flowbrigade_redis_integration.nim
redis-cli -h 127.0.0.1 -p 6380 SHUTDOWN NOSAVE
```

Docker is also fine when the container publishes a local port:

```sh
docker run --rm -d --name flowbrigade-redis -p 6380:6379 redis:7-alpine
FLOWBRIGADE_REDIS_HOST=127.0.0.1 FLOWBRIGADE_REDIS_PORT=6380 nimble benchmarkRedis
docker stop flowbrigade-redis
```

Start Redis for a local integration run:

```sh
sudo systemctl start redis-server
```

Stop it after the run:

```sh
sudo systemctl stop redis-server
```

Check current state:

```sh
systemctl is-active redis-server
systemctl is-enabled redis-server
redis-cli ping
```

The Redis integration tests default to `127.0.0.1:6379`. Override the target
when needed:

```sh
FLOWBRIGADE_REDIS_HOST=127.0.0.1 FLOWBRIGADE_REDIS_PORT=6379 nim r -p:packages/flowbrigade_redis/src -p:src packages/flowbrigade_redis/tests/test_flowbrigade_redis_integration.nim
```

## Memcached

For one-off verification without enabling a system service, start Memcached on a
temporary port:

```sh
memcached -l 127.0.0.1 -p 11212 -U 0 -P /tmp/flowbrigade-memcached.pid -d
FLOWBRIGADE_MEMCACHED_HOST=127.0.0.1 FLOWBRIGADE_MEMCACHED_PORT=11212 nim r -p:packages/flowbrigade_memcached/src -p:src packages/flowbrigade_memcached/tests/test_flowbrigade_memcached_integration.nim
kill "$(cat /tmp/flowbrigade-memcached.pid)"
```

Start Memcached for a local integration run:

```sh
sudo systemctl start memcached
```

Stop it after the run:

```sh
sudo systemctl stop memcached
```

Check current state:

```sh
systemctl is-active memcached
systemctl is-enabled memcached
```

The Memcached integration test defaults to `127.0.0.1:11211`. Override the
target when needed:

```sh
FLOWBRIGADE_MEMCACHED_HOST=127.0.0.1 FLOWBRIGADE_MEMCACHED_PORT=11211 nim r -p:packages/flowbrigade_memcached/src -p:src packages/flowbrigade_memcached/tests/test_flowbrigade_memcached_integration.nim
```
