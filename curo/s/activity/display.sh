#!/usr/bin/env bash
. ~/.curo/config.sh

left_title="Curo : Current activity"
right_title="$( uptime )"

spacing=$(( COLUMNS - ${#left_title} - ${#right_title} - 2 ))

title="$( printf "%s%${spacing}s%s" "$left_title" "" "$right_title" )"

clear
echo " $title"
line="$( printf "%${COLUMNS}s" )"
printf "%s\n\n" "${line// /-}"

cat ~/.curo/s/activity/query.1.out
rm ~/.curo/s/activity/query.1.out
