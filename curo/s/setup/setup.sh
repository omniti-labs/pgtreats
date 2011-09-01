#!/usr/bin/env bash
. ~/.curo/c/set_terminal_size

. ~/.curo/c/find_all_actions
. ~/.curo/c/dialog_menu
. ~/.curo/c/get_keybindings

find_all_actions

while true
do
    get_keybindings
    dialog=()

    for f in {1..8}
    do
        i=$(( f - 1 ))

        dialog[$(( i * 2 ))]="$f"
        dialog[$(( i * 2 + 1 ))]="Action for F$f : ${r_get_keybindings[$f]}"
    done

    dialog_menu "${dialog[@]}"
    use_key="$r_dialog_menu"

    commands=(menu)
    dialog=(0 menu)

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

    dialog_backtitle="Curo : Setup"
    dialog_menutitle="Action for F$use_key:"

    dialog_menu "${dialog[@]}"
    use_idx="$r_dialog_menu"
    use_action="${commands[$use_idx]}"

    printf '\\i ~/.curo/s/%q.sql\n' "$use_action" > ~/.curo/k/f${use_key}.sql
done
