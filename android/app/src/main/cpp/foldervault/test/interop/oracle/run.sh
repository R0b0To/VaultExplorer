#!/bin/bash
# Runs the OFFICIAL cryptofs (the library inside Cryptomator) as an oracle: ./run.sh <cmd> <vault> <pw> [args...]
# Needs a JDK 21 (the source launcher compiles Official.java) and the jars from ./fetch_oracle.sh.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${ORACLE_LIB:-$HERE/lib}"
[ -d "$LIB" ] || { echo "no $LIB -- run $HERE/fetch_oracle.sh first" >&2; exit 2; }
export LC_ALL=C.UTF-8 LANG=C.UTF-8 JAVA_TOOL_OPTIONS="-Dsun.jnu.encoding=UTF-8 -Dfile.encoding=UTF-8"
exec java -Dlogback.configurationFile="$HERE/logback.xml" -cp "$LIB/*" "$HERE/Official.java" "$@" 2> >(grep -v "Picked up JAVA_TOOL_OPTIONS" >&2)
