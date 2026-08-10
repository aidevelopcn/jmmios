#!/bin/bash
# 兼容旧命令：./scripts/package.sh → ./scripts/build_ipa.sh
exec "$(cd "$(dirname "$0")" && pwd)/build_ipa.sh" "$@"
