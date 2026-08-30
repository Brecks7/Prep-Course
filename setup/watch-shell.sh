#!/usr/bin/env bash
# watch-shell.sh — el journal de GNOME Shell, filtrado a lo que importa.
#
# Una extensión que falla no avisa: `gnome-extensions info` sigue diciendo
# ACTIVE aunque enable() haya tirado a mitad de camino. Lo único que lo cuenta
# es el journal del usuario, y ahí adentro hay demasiado ruido para leerlo.
#
#   bash setup/watch-shell.sh            # seguir en vivo
#   bash setup/watch-shell.sh --since -1h
#   bash setup/watch-shell.sh --boot     # todo lo de este arranque, sin -f

set -uo pipefail

PATRON='mactahoe|macos-dock|macosdock|blur-my-shell|JS ERROR|JS WARNING|Extension .* (error|no puede)|has been already disposed'

MODO=(-f)
case "${1:-}" in
    --since) MODO=(--since "$2" --no-pager) ;;
    --boot)  MODO=(-b --no-pager) ;;
esac

printf '  filtro: %s\n\n' "$PATRON"
journalctl --user "${MODO[@]}" -o cat 2>/dev/null | grep --line-buffered -E "$PATRON"
