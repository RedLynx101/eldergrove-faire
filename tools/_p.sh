cd ~/parkbend
PERF=$(ls /usr/lib/linux-tools/*/perf | head -1)
$PERF record -F 999 -g -o $HOME/park.perf -- ${B:-./park} --bench 600 1500 ${M:-0} 700 2>&1 | tail -1
$PERF report -i $HOME/park.perf --no-children --sort symbol --stdio 2>/dev/null | grep -v '^#' | grep '%' | grep -v '^ *|' | grep -v -- '--' | head -40
