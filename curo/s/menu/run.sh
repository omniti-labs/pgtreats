#!/usr/bin/env bash
. ~/.curo/config.sh

. ~/.curo/c/find_all_actions
. ~/.curo/c/dialog_menu

sql=~/.curo/s/menu/run.sql
rm -f "$sql"
touch "$sql"

commands=(setup)
dialog=(0 setup)

find_all_actions

i=0
max_i="${#r_find_all_actions_action[*]}"

while (( i < max_i ))
do
    o=$(( i + 1 ))
    commands[$o]="${r_find_all_actions_action[$i]}"
    dialog[$(( o * 2 ))]="$o"
    dialog[$(( o * 2 +1 ))]="${r_find_all_actions_name[$i]}"
    (( i++ ))
done

dialog_menu "${dialog[@]}"
use_idx="$r_dialog_menu"

(
    printf "\\i ~/.curo/s/%q.sql\n" "${commands[$use_idx]}"
    if (( $use_idx > 0 ))
    then
        if [[ ${r_find_all_actions_wait[$(( $use_idx - 1 )) ]} == "wait" ]]
        then
            echo "\\prompt 'press enter> ' _"
        fi
    fi
    echo "\\i ~/.curo/s/menu.sql"
) > "$sql"

