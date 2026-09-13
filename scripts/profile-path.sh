#!/bin/sh

# harness-docker runs login shells on Alpine, whose /etc/profile resets PATH
# and would otherwise drop tool locations added by image ENV PATH directives.
case ":$PATH:" in
  *:/usr/local/go/bin:*) ;;
  *) PATH="/usr/local/go/bin:$PATH" ;;
esac

case ":$PATH:" in
  *:/usr/local/custom-bin:*) ;;
  *) PATH="/usr/local/custom-bin:$PATH" ;;
esac

case ":$PATH:" in
  *:"$HOME"/.local/bin:*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac

export PATH
