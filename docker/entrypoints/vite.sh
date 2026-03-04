#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

BUNDLE="bundle check"

until $BUNDLE
do
	bundle install
	sleep 2;
done

pnpm store prune
pnpm install --force

echo "Ready to run Vite development server."

exec "$@"
