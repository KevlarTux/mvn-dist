#!/usr/bin/env bash

### Layout functions
move_cursor_up() {
    printf "\\033[%qA" "${1}"
}

move_cursor_down() {
    printf "\\033[%qB" "${1}"
}

move_cursor_forward() {
    printf "\\033[%qC" "${1}"
}

move_cursor_backward() {
    printf "\\033[%qD" "${1}"
}

save_cursor_position() {
    printf "\\033[s"
}

recall_cursor_position() {
    printf "\\033[u"
}

delete_until_eol() {
    printf "\\033[0K"
}
### /Layout functions
