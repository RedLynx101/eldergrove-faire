cd ~/parkbend
PERF=$(ls /usr/lib/linux-tools/*/perf | head -1)
$PERF record --call-graph dwarf,16384 -F 250 -o $HOME/park.perf -- ./park --bench 400 1500 0 700 2>&1 | tail -1
for s in term_drop span_fade; do
$PERF report -i $HOME/park.perf --no-children --symbols $s -g caller,1.5,callee,function,percent --stdio 2>/dev/null | grep -v '^#' | grep -v '^$' | grep -v "pool_work\|start_thread\|clone3" | head -40
done
