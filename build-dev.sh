#!/usr/bin/env bash

if pgrep -x "ReadItSoonCompanion" >/dev/null 2>&1; then
  pkill -x "ReadItSoonCompanion"
fi

BASE_URL=https://readitsoon.chiq.me ./build.sh

open ./ReadItSoonCompanion.app
