# Source from ~/.zshrc. Resolve paths from this file, not the current directory.
typeset -g VYNIC_DEV_TOOL_DIR="${${(%):-%x}:A:h}"
unalias vynic-pos vynic-manager 2>/dev/null
function vynic-pos() {
  python3 "$VYNIC_DEV_TOOL_DIR/dev.py" pos "$@"
}
function vynic-manager() {
  python3 "$VYNIC_DEV_TOOL_DIR/dev.py" manager "$@"
}
