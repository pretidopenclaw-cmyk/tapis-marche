#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Vitesse du tapis
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🚶
# @raycast.packageName Tapis Marche
# @raycast.argument1 { "type": "text", "placeholder": "km/h" }

open -g "tapismarche://vitesse/$1"
