# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################
# MISC (For dots/.config/* but not quickshell, not fish, not Hyprland, not fontconfig)
case "${SKIP_MISCCONF}" in
  true) true;;
  *)
    for i in $(find dots/.config/ -mindepth 1 -maxdepth 1 ! -name 'quickshell' ! -name 'fish' ! -name 'hypr' ! -name 'fontconfig' ! -name 'illogical-impulse' -exec basename {} \;); do
#      i="dots/.config/$i"
      echo "[$0]: Found target: dots/.config/$i"
      if [ -d "dots/.config/$i" ];then install_dir__sync "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      elif [ -f "dots/.config/$i" ];then install_file "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      fi
    done
    install_dir "dots/.local/share/konsole" "${XDG_DATA_HOME}"/konsole
    ;;
esac

# This fork's Hyprland and Quickshell profile calls small user-owned helpers
# (OBS control, VM reporting, Focus Mode, and display recovery). Install only
# the files shipped by the repository and preserve unrelated local binaries.
if [[ -d dots/.local/bin && ( "${SKIP_QUICKSHELL}" != true || "${SKIP_HYPRLAND}" != true ) ]]; then
  install_dir dots/.local/bin "$XDG_BIN_HOME"
fi

case "${SKIP_QUICKSHELL}" in
  true) true;;
  *)
    # Install the current shell layout on a fresh profile without deleting the
    # shell's runtime backups/translations on an existing machine. @HOME@ keeps
    # the public template portable and is expanded only in the destination copy.
    profile_config="profile/illogical-impulse/config.json"
    if [[ -f "$profile_config" ]]; then
      target_config="$XDG_CONFIG_HOME/illogical-impulse/config.json"
      install_file__auto_backup "$profile_config" "$target_config"
      for installed_config in "$target_config" "$target_config.new"; do
        if [[ -f "$installed_config" ]] && grep -q '@HOME@' "$installed_config"; then
          sed -i "s|@HOME@|$HOME|g" "$installed_config"
        fi
      done
    fi
     # Should overwriting the whole directory not only ~/.config/quickshell/ii/ cuz https://github.com/end-4/dots-hyprland/issues/2294#issuecomment-3448671064
    install_dir__sync dots/.config/quickshell "$XDG_CONFIG_HOME"/quickshell
    ;;
esac

case "${SKIP_FISH}" in
  true) true;;
  *)
    install_dir__sync_exclude dots/.config/fish "$XDG_CONFIG_HOME"/fish "conf.d"
    ;;
esac

case "${SKIP_FONTCONFIG}" in
  true) true;;
  *)
    case "$FONTSET_DIR_NAME" in
      "") install_dir__sync dots/.config/fontconfig "$XDG_CONFIG_HOME"/fontconfig ;;
      *) install_dir__sync dots-extra/fontsets/$FONTSET_DIR_NAME "$XDG_CONFIG_HOME"/fontconfig ;;
    esac;;
esac

# For Hyprland
case "${SKIP_HYPRLAND}" in
  true) true;;
  *)
    install_dir__sync dots/.config/hypr/hyprland "$XDG_CONFIG_HOME"/hypr/hyprland
    if [ -f "${XDG_CONFIG_HOME}/hypr/hyprland.conf" ]; then
      mv "${XDG_CONFIG_HOME}/hypr/hyprland.conf" "${XDG_CONFIG_HOME}/hypr/hyprland.conf.old" # disable old config
      echo 'hyprland.conf has been renamed to hyprland.conf.old. This is to allow the new lua config to load.'
    fi
    for i in hyprlock.conf ; do
      install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
    done
    for i in hyprland.lua ; do
      case "${SKIP_HYPRLAND_ENTRY}" in
        true) true;;
        *) install_file "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i" ;;
      esac
    done
    for i in hypridle.conf ; do
      if [[ "${INSTALL_VIA_NIX}" == true ]]; then
        install_file__auto_backup "dots-extra/via-nix/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      else
        install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      fi
    done
    if [ "$OS_GROUP_ID" = "fedora" ];then
      v bash -c "printf \"# For fedora to setup polkit\nexec-once = /usr/libexec/kf6/polkit-kde-authentication-agent-1\n\" >> ${XDG_CONFIG_HOME}/hypr/hyprland/execs.conf"
    fi

    install_dir__ignore_existing "dots/.config/hypr/custom" "${XDG_CONFIG_HOME}/hypr/custom"
    ;;
esac

install_file "dots/.local/share/icons/illogical-impulse.svg" "${XDG_DATA_HOME}"/icons/illogical-impulse.svg
