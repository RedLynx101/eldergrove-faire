cd ~/parkbend
PERF=$(ls /usr/lib/linux-tools/*/perf | head -1)
$PERF record --call-graph dwarf,16384 -F 250 -o $HOME/park.perf -- ./park --bench 500 1500 ${M:-1} 700 2>&1 | tail -1
$PERF report -i $HOME/park.perf --children --sort symbol --stdio 2>/dev/null | grep -E '^ +[0-9]' | grep 'WL_FID' | head -40
