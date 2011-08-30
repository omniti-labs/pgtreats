#!/bin/bash
fifo=~/.curo/s/activity/fifo
rm -f "$fifo"

mkfifo "$fifo"

while true
do
    echo "\\o ~/.curo/s/activity/query.1.out"
    echo "\\i ~/.curo/s/activity/query.1.sql"
    echo "\\o"
    echo "\\! ~/.curo/s/activity/display.sh"
    sleep 1
done > "$fifo" 2>/dev/null < /dev/null &
