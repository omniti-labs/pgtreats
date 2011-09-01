#!/usr/bin/env bash
. ~/.curo/c/set_terminal_size

fifo=~/.curo/s/activity/fifo
rm -f "$fifo"

mkfifo "$fifo"

display_sh="$HOME/.curo/s/activity/display.sh"

while true
do
    echo "\\o ~/.curo/s/activity/query.1.out"
    echo "\\i ~/.curo/s/activity/query.1.sql"
    echo "\\o"
    echo "\\! $display_sh"
    sleep 1
done > "$fifo" 2>/dev/null < /dev/null &
