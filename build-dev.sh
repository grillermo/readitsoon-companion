#!/usr/bin/env bash

if pgrep -x "ReadItSoonCompanion" >/dev/null 2>&1; then
  pkill -x "ReadItSoonCompanion"
fi

BASE_URL=https://readitsoon.chiq.me \
  USER_EMAIL=guillermo.siliceo@kindle.com \
  AUTH_TOKEN=56411c906131ab10419d8216968afc369b09ecd28717edbe2e8cca55b8f3c653 \
  ./build.sh

open ./ReadItSoonCompanion.app
