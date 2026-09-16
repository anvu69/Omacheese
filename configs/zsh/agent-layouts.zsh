# Agent layouts for tmux - ported from Omarchy's default/bash/fns/tmux.
#
#   tdl <ai> [ai2]    editor + agent + terminal in one window
#   tds               editor / diff / terminal / agent in a 2x2
#   tdlm <ai> [ai2]   one tdl window per subdirectory of $PWD
#   tsl <n> <cmd>     n tiled panes all running the same command
#
# The point of these is watching an agent work rather than talking to it in a
# bare shell: the editor stays visible beside it, and tdlm puts a whole tree of
# projects side by side, one agent each, switchable with Alt+1..9.
#
# The herdr equivalents are hdl/hds/hdlm/hsl in the PowerShell profile. Same
# four layouts, same argument order, because the two are meant to be
# interchangeable - see docs/agent-panes.md.
#
# <ai> is whatever starts your agent: claude, codex, gemini, opencode.
#
# zsh only. Arrays here are 1-indexed, so ${panes[1]} is the first pane and
# ${panes[-1]} the last. Sourced from zshrc; do not source this from bash,
# where ${panes[1]} would silently mean the second element instead.

# Editor left, agent right, a short terminal underneath.
# Usage: tdl <ai> [second_ai]
tdl() {
  [ -z "$1" ] && { echo "Usage: tdl <ai> [second_ai]"; return 1; }
  [ -z "$TMUX" ] && { echo "tdl needs to run inside tmux."; return 1; }

  local current_dir="$PWD"
  local ai="$1" ai2="$2"
  local editor_pane ai_pane ai2_pane

  # $TMUX_PANE, not the active pane: this stays correct if focus moves while
  # the layout is still being built.
  editor_pane="$TMUX_PANE"

  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"
  tmux split-window -v -l 15% -t "$editor_pane" -c "$current_dir"
  ai_pane=$(tmux split-window -h -l 30% -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')

  if [ -n "$ai2" ]; then
    ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
    tmux send-keys -t "$ai2_pane" "$ai2" C-m
  fi

  tmux send-keys -t "$ai_pane" "$ai" C-m
  tmux send-keys -t "$editor_pane" "${EDITOR:-nvim} ." C-m

  # Omarchy's copy selects $opencode_pane here, which is only ever set in tds -
  # under `set -u` that is an unbound variable, and without it tmux just gets an
  # empty -t. Focus belongs on the editor.
  tmux select-pane -t "$editor_pane"
}

# Editor, live diff, terminal and agent in four equal quarters.
# Usage: tds [ai]
tds() {
  [ -z "$TMUX" ] && { echo "tds needs to run inside tmux."; return 1; }

  local current_dir="$PWD"
  local ai="${1:-opencode}"
  local editor_pane diff_pane terminal_pane ai_pane

  editor_pane="$TMUX_PANE"
  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"

  terminal_pane=$(tmux split-window -v -l 50% -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  diff_pane=$(tmux split-window -h -l 50% -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  ai_pane=$(tmux split-window -h -l 50% -t "$terminal_pane" -c "$current_dir" -P -F '#{pane_id}')

  tmux send-keys -t "$editor_pane" "${EDITOR:-nvim} ." C-m
  # Omarchy runs `hunk diff --watch` here. hunk is not packaged for AlmaLinux,
  # so this uses git's own watch loop - same job, nothing extra to install.
  tmux send-keys -t "$diff_pane" "while true; do clear; git diff --stat HEAD; sleep 2; done" C-m
  tmux send-keys -t "$ai_pane" "$ai" C-m

  tmux select-pane -t "$editor_pane"
}

# One tdl window per subdirectory: a whole tree of projects, an agent each.
# Usage: tdlm <ai> [second_ai]
tdlm() {
  [ -z "$1" ] && { echo "Usage: tdlm <ai> [second_ai]"; return 1; }
  [ -z "$TMUX" ] && { echo "tdlm needs to run inside tmux."; return 1; }

  local ai="$1" ai2="$2"
  local base_dir="$PWD"
  local first=1 dir dirpath pane_id

  # tmux rejects dots and colons in session names.
  tmux rename-session "$(basename "$base_dir" | tr '.:' '--')"

  for dir in "$base_dir"/*/; do
    [ -d "$dir" ] || continue
    dirpath="${dir%/}"

    if [ "$first" -eq 1 ]; then
      tmux send-keys -t "$TMUX_PANE" "cd '$dirpath' && tdl $ai $ai2" C-m
      first=0
    else
      pane_id=$(tmux new-window -c "$dirpath" -P -F '#{pane_id}')
      tmux send-keys -t "$pane_id" "tdl $ai $ai2" C-m
    fi
  done
}

# n tiled panes, the same command in each. For running one agent several times
# over the same tree and picking whichever answer lands first.
# Usage: tsl <pane_count> <command>
tsl() {
  [ -z "$1" ] || [ -z "$2" ] && { echo "Usage: tsl <pane_count> <command>"; return 1; }
  [ -z "$TMUX" ] && { echo "tsl needs to run inside tmux."; return 1; }

  local count="$1" cmd="$2"
  local current_dir="$PWD"
  local panes=() new_pane pane

  tmux rename-window -t "$TMUX_PANE" "$(basename "$current_dir")"
  panes+=("$TMUX_PANE")

  while [ "${#panes[@]}" -lt "$count" ]; do
    new_pane=$(tmux split-window -h -t "${panes[-1]}" -c "$current_dir" -P -F '#{pane_id}')
    panes+=("$new_pane")
    tmux select-layout -t "${panes[1]}" tiled
  done

  for pane in "${panes[@]}"; do
    tmux send-keys -t "$pane" "$cmd" C-m
  done

  tmux select-pane -t "${panes[1]}"
}
