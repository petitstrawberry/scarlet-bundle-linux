#!/bin/sh
set -eu

# The distribution's Vulkan loader selects the Scarlet SGFX ICD.
export LD_LIBRARY_PATH=/usr/lib:/lib
export VK_DRIVER_FILES=/etc/vulkan/icd.d/sgfx.json
export SDL_VIDEODRIVER=sws
export SDL_AUDIODRIVER=dummy

exec /usr/bin/supertuxkart --render-driver=vulkan "$@"
