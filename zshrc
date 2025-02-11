########################################################################
# Monolithic Optimized Zsh Configuration
#
# This file implements a set of advanced interactive features:
#  - Global feature toggles to enable/disable modules.
#  - Robust history management.
#  - Advanced tab completion with menu–select.
#  - Minimal syntax highlighting and autosuggestions.
#  - Modular prompt construction that shows:
#       user@host, current directory, Docker container,
#       Python venv, Git branch, directory stack summary.
#  - Right prompt with current time.
#  - Command duration measurement and exit-status notifications.
#  - Extra utility functions: cgtop (cd to Git repo root) and explain.
#  - Auto-listing directory contents after cd.
#  - Optional FZF–based history search.
#  - Aggressive path expansion and custom keybindings.
########################################################################

#############################
# 1. Global Feature Toggles #
#############################
# Each toggle is set to 1 (enabled) by default. To disable any module,
# set its variable to 0 (e.g. in an earlier config file or before sourcing).

: ${ZSH_FEATURE_SYNTAX_HIGHLIGHT:=1}      # Syntax highlighting (minimal)
: ${ZSH_FEATURE_AUTOSUGGEST:=1}           # Autosuggestions (minimal)
: ${ZSH_FEATURE_GIT:=1}                   # Git branch display in prompt
: ${ZSH_FEATURE_DOCKER_PROMPT:=1}         # Detect Docker container
: ${ZSH_FEATURE_PYTHON_VENV_PROMPT:=1}    # Show Python virtualenv in prompt
: ${ZSH_FEATURE_SYSTEM_LOAD:=1}           # Show system load average
: ${ZSH_FEATURE_DIR_STACK:=1}             # Display part of the directory stack
: ${ZSH_FEATURE_RPROMPT_TIME:=1}          # Show current time in right prompt
: ${ZSH_FEATURE_COMMAND_DURATION:=1}      # Display duration of last command
: ${ZSH_FEATURE_EXIT_STATUS:=1}           # Notify if last command failed
: ${ZSH_FEATURE_CD_TO_GIT_ROOT:=1}         # Provide “cgtop” to jump to Git root
: ${ZSH_FEATURE_EXPLAIN:=1}               # Provide “explain” utility for commands
: ${ZSH_FEATURE_AUTO_LS_AFTER_CD:=1}      # Auto-run ls after directory change
: ${ZSH_FEATURE_FZF_HISTORY:=0}           # Enable FZF-based history search (requires fzf)
: ${ZSH_FEATURE_PATH_EXPANSION:=1}        # Enable aggressive path expansion
: ${ZSH_FEATURE_KEYBINDINGS:=1}           # Custom keybindings & ZLE widgets
: ${ZSH_FEATURE_LS_COLORS:=1}             # Custom LS_COLORS settings

#############################
# 2. Basic Environment      #
#############################
# History settings and shell options

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS SHARE_HISTORY

# Enable extended globbing and auto-cd features if path expansion is on
if (( ZSH_FEATURE_PATH_EXPANSION )); then
  setopt EXTENDED_GLOB AUTO_CD CDABLE_VARS AUTO_NAME_DIR
fi

#############################
# 3. Tab Completion         #
#############################
# Initialize Zsh completion system and enable menu-select.
autoload -Uz compinit && compinit

# Use zstyle to format the completions
zstyle ':completion:*:descriptions' format '%F{blue}%d%f'
zstyle ':completion:*:warnings' format '%F{red}No matches for: %d%f'
zstyle ':completion:*' menu select=long

#############################
# 4. Minimal Syntax Highlight #
#############################
if (( ZSH_FEATURE_SYNTAX_HIGHLIGHT )); then
  # This minimal highlighter simply marks the first token red if it is not found.
  function _syntax_highlight() {
    local buf=$BUFFER
    # Extract first token (command)
    local cmd=${buf%% *}
    # If nonempty and command is not found in PATH, wrap it in red escape sequences.
    if [[ -n $cmd && -z $(whence -p "$cmd") ]]; then
      BUFFER="%{$fg[red]%}$buf%{$reset_color%}"
      zle reset-prompt
    fi
  }
  # Register _syntax_highlight to be run before each redraw.
  zle -N _syntax_highlight
  autoload -Uz add-zle-hook-widget && add-zle-hook-widget line-pre-redraw _syntax_highlight
fi

#############################
# 5. Minimal Autosuggestions #
#############################
if (( ZSH_FEATURE_AUTOSUGGEST )); then
  # A minimal autosuggestion: search history for a command starting with LBUFFER.
  function _autosuggest() {
    local prefix=$LBUFFER suggestion=""
    # Search history (most recent first) for a line that begins with the current input.
    suggestion=$(fc -rl 1 | grep -m 1 "^${prefix}")
    if [[ -n $suggestion ]]; then
      # Remove the already typed portion.
      suggestion=${suggestion#$prefix}
      # Append suggestion to the right prompt in a faint color.
      ZLE_RPROMPT="%{$fg[black]%}$suggestion%{$reset_color%}"
    else
      ZLE_RPROMPT=""
    fi
    zle reset-prompt
  }
  # Register _autosuggest to run before each redraw.
  zle -N _autosuggest
  add-zle-hook-widget line-pre-redraw _autosuggest
fi

#############################
# 6. Prompt Segments        #
#############################
# Define functions that return parts of the prompt.

# 6.1 Git branch detection
function _prompt_git_branch() {
  if (( ZSH_FEATURE_GIT )); then
    if git rev-parse --is-inside-work-tree &>/dev/null; then
      local branch
      branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
      [[ -n $branch ]] && echo "%F{magenta}($branch)%f "
    fi
  fi
}

# 6.2 Docker container detection
function _prompt_docker() {
  if (( ZSH_FEATURE_DOCKER_PROMPT )); then
    if grep -q 'docker' /proc/1/cgroup 2>/dev/null; then
      local cid
      cid=$(grep 'docker' /proc/self/cgroup | sed 's|.*docker/[^/]*.*|\1|' | head -n1)
      [[ -n $cid ]] && echo "%F{green}docker:${cid:0:8}%f "
    fi
  fi
}

# 6.3 Python virtual environment
function _prompt_venv() {
  if (( ZSH_FEATURE_PYTHON_VENV_PROMPT )) && [[ -n "$VIRTUAL_ENV" ]]; then
    local venv=${VIRTUAL_ENV##*/}
    echo "%F{cyan}[$venv]%f "
  fi
}

# 6.4 System load display
function _prompt_load() {
  if (( ZSH_FEATURE_SYSTEM_LOAD )); then
    local load
    load=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    [[ -n $load ]] && echo "%F{yellow}load:$load%f "
  fi
}

# 6.5 Directory stack summary
function _prompt_dirstack() {
  if (( ZSH_FEATURE_DIR_STACK )) && (( ${#dirstack[@]} > 1 )); then
    echo "(StackTop=${dirstack[1]}) "
  fi
}

# 6.6 Right prompt: current time display
function _prompt_time() {
  if (( ZSH_FEATURE_RPROMPT_TIME )); then
    echo "%F{yellow}%*%f"
  fi
}

#############################
# 7. Build the Prompt       #
#############################
# Concatenate the segments to build the left (PROMPT) and right (RPROMPT) parts.
function _build_prompt() {
  PROMPT="%B%F{blue}%n@%m%f%b:%B%F{green}%~%f%b "  # user@host:current-directory
  PROMPT+=$(_prompt_docker)
  PROMPT+=$(_prompt_venv)
  PROMPT+=$(_prompt_git_branch)
  PROMPT+=$(_prompt_dirstack)
  PROMPT+="%# "  # prompt symbol: % for user, # for root
  RPROMPT=$(_prompt_time)
}
_build_prompt

#############################
# 8. Command Timing & Exit  #
#############################
# Measure the duration of the last command and print exit status if nonzero.
typeset -g __cmd_start=0
typeset -g __cmd_duration=0

# Before a command executes, record the time.
function preexec() {
  __cmd_start=$EPOCHSECONDS
}
zle -N preexec

# After the command, compute its duration and check exit status.
function precmd() {
  if (( ZSH_FEATURE_COMMAND_DURATION )); then
    __cmd_duration=$(( EPOCHSECONDS - __cmd_start ))
    if (( __cmd_duration > 0 )); then
      echo "%F{cyan}[Cmd took: ${__cmd_duration}s]%f"
    fi
  fi
  if (( ZSH_FEATURE_EXIT_STATUS )) && (( $? != 0 )); then
    echo "%B%F{red}[Exit: $?]%f%b"
  fi
  _build_prompt  # refresh prompt (in case directory or context changed)
}
zle -N precmd

#############################
# 9. Utility Functions      #
#############################

# 9.1 cgtop: change directory to Git repository root
if (( ZSH_FEATURE_CD_TO_GIT_ROOT )); then
  function cgtop() {
    if git rev-parse --is-inside-work-tree &>/dev/null; then
      cd "$(git rev-parse --show-toplevel)" || return
    else
      echo "Not inside a Git repository."
    fi
  }
fi

# 9.2 explain: provide basic command information
if (( ZSH_FEATURE_EXPLAIN )); then
  function explain() {
    if [[ -z "$1" ]]; then
      echo "Usage: explain <command>"
      return 1
    fi
    echo "----- Command Info -----"
    whence -v "$1"
    echo ""
    echo "----- Man Page Summary -----"
    man -f "$1" 2>/dev/null || echo "No man page found."
  }
fi

#############################
# 10. Auto-listing on cd    #
#############################
if (( ZSH_FEATURE_AUTO_LS_AFTER_CD )); then
  function chpwd() {
    ls --color=auto
  }
fi

#############################
# 11. Custom LS_COLORS      #
#############################
if (( ZSH_FEATURE_LS_COLORS )); then
  export LS_COLORS="di=1;34:ln=36:so=35:pi=33:ex=1;32:*.md=1;35:*.txt=0;32"
fi

#############################
# 12. Optional FZF History  #
#############################
if (( ZSH_FEATURE_FZF_HISTORY )); then
  if command -v fzf >/dev/null; then
    function fzf-history-widget() {
      local selected
      selected=$(fc -l 1 | sort -r | fzf +s +m --ansi)
      if [[ -n $selected ]]; then
        LBUFFER=${selected#* }
        zle redisplay
      fi
    }
    zle -N fzf-history-widget
    bindkey '^R' fzf-history-widget
  fi
fi

#############################
# 13. Custom Keybindings     #
#############################
if (( ZSH_FEATURE_KEYBINDINGS )); then
  bindkey -e  # use Emacs-style keybindings
  bindkey '^P' up-line-or-history
  bindkey '^N' down-line-or-history
  # Example: Alt+L clears the screen, runs ls, and resets the prompt.
  function clear_ls_widget() {
    clear
    ls --color=auto
    zle reset-prompt
  }
  zle -N clear_ls_widget
  bindkey '^[l' clear_ls_widget  # ESC + l (Alt+L)
fi

#############################
# 14. Aggressive Path Expansion #
#############################
# (Already enabled via AUTO_CD, CDABLE_VARS, AUTO_NAME_DIR, etc.)

########################################################################
# End of Monolithic Configuration
########################################################################
