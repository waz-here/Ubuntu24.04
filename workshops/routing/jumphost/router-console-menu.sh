#!/usr/bin/env bash
set -u

HOST="192.168.30.254"

while true; do
    clear
    echo "Routing Workshop - Instructor AUX Console"
    echo
    for i in $(seq 1 14); do
        printf " %2d) Router r%02d\n" "$i" "$i"
    done
    echo
    echo "  q) Quit"
    echo
    read -r -p "Select router [1-14]: " choice

    case "$choice" in
        q|Q) exit 0 ;;
        ''|*[!0-9]*)
            echo "Invalid selection."
            sleep 1
            ;;
        *)
            if (( choice >= 1 && choice <= 14 )); then
                port=$((3000 + choice))
                printf "\nConnecting to Router r%02d AUX console on %s:%d\n" "$choice" "$HOST" "$port"
                echo "Telnet escape sequence: Ctrl-] then type quit"
                echo
                /usr/bin/telnet "$HOST" "$port"
                echo
                read -r -p "Press Enter to return to the router menu..." _
            else
                echo "Invalid selection."
                sleep 1
            fi
            ;;
    esac
done
