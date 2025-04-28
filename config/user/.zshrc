# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Si vienes de bash, puede que tengas que cambiar tu $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Establecer la ruta de instalación de Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

# Si el PATH no está configurado correctamente, ajustamos el PATH.
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Habilitar autocompletado
autoload -U compinit && compinit

# Habilitar colores en la terminal
autoload -U colors && colors

# Activar el autocorrector de comandos
setopt correct

# Configuración del historial
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

# Evitar que se guarden comandos duplicados en el historial
setopt hist_ignore_dups

# Establecer el tema de Zsh
ZSH_THEME="powerlevel10k/powerlevel10k"

# Establecer los plugins a cargar
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  fzf
  # ssh-agent
)


# Cargar Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Configuración de alias
alias ls="ls --color=auto"
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias grep="grep --color=auto"
alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --all'
alias gco='git checkout'
alias gst='git stash'
alias gpl='git pull'
alias sshconfig='nvim ~/.ssh/config'
alias ..='cd ..'
alias ...='cd ../..'
alias ports='lsof -i -P -n | grep LISTEN'
alias myip='curl ifconfig.me'
alias reload!='source ~/.zshrc'


# Configuración del prompt (puedes cambiar "agnoster" por otro tema)
# autoload -U promptinit; promptinit
# prompt robbyrussell

# Activar la barra de autocompletado
bindkey "^I" expand-or-complete

# Compartir historial entre sesiones de terminal
setopt share_history

# Habilitar "autojump" para navegación rápida entre directorios
[[ -s $HOMEBREW_PREFIX/share/autojump/autojump.zsh ]] && source $HOMEBREW_PREFIX/share/autojump/autojump.zsh

# Habilitar fzf para búsqueda rápida de archivos y comandos
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Puedes cargar alias y funciones adicionales desde un archivo separado
if [ -f "$HOME/.zsh_aliases" ]; then
    source "$HOME/.zsh_aliases"
fi

# Personalización del editor en función de si estás en una sesión SSH o local
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

# Cargar configuraciones personalizadas si existe el archivo
# Puedes eliminar o ajustar esta línea si no usas configuraciones personalizadas
# source "$ZSH_CUSTOM/my_config.zsh"  # Asegúrate de tener este archivo si quieres separarlo

# Opciones para actualización automática de Oh My Zsh
# zstyle ':omz:update' mode auto  # Descomenta para habilitar actualizaciones automáticas

# Habilitar la corrección automática de comandos
ENABLE_CORRECTION="true"

# Deshabilitar título de terminal automático
# DISABLE_AUTO_TITLE="true"

# Otros ajustes de Oh My Zsh
# Uncomment if you prefer case-sensitive completion
# CASE_SENSITIVE="true"
# Uncomment if you want hyphen-insensitive completion
# HYPHEN_INSENSITIVE="true"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
