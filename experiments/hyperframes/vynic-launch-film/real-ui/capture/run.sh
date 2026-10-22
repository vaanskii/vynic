#!/bin/bash
# Run a capture test with the local clock shifted to ~20:40 (dinner service), via TZ.
cd "$(dirname "$0")/../.."
h=$(date -u +%H); m=$(date -u +%M)
off=$(python3 -c "u=int('$h')+int('$m')/60; o=round(20.7-u); o=(o+12)%24-12; print(o)")
if [ "$off" -ge 0 ]; then tz="Etc/GMT-$off"; else tz="Etc/GMT+${off#-}"; fi
echo "TZ=$tz"
TZ=$tz flutter test "$@" --update-goldens
