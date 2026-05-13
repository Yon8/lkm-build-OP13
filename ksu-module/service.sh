#!/system/bin/sh

MODDIR=${0%/*}
LOG_TAG=nohello
KO_PATH="$MODDIR/nohello.ko"
CONFIG_PATH="$MODDIR/target_path.conf"
HIDE_DIRENTS_CONFIG="$MODDIR/hide_dirents.conf"
SCOPE_MODE_CONFIG="$MODDIR/scope_mode.conf"
DENY_UIDS_CONFIG="$MODDIR/deny_uids.conf"
DENY_PACKAGES_CONFIG="$MODDIR/deny_packages.conf"
TARGET_WAIT_SECONDS_CONFIG="$MODDIR/target_wait_seconds.conf"
PACKAGE_WAIT_SECONDS_CONFIG="$MODDIR/package_wait_seconds.conf"
DEFAULT_TARGET_PATH="/data/local/tmp/nohello"
TARGET_PATHS=""
HIDE_DIRENTS=1
SCOPE_MODE=global
DENY_UIDS=""
TARGET_WAIT_SECONDS=60
PACKAGE_WAIT_SECONDS=60
UNRESOLVED_PACKAGES=0

log_i() {
	log -p i -t "$LOG_TAG" "$*"
}

log_e() {
	log -p e -t "$LOG_TAG" "$*"
}

add_target_path() {
	CANDIDATE_PATH="$1"

	if [ -z "$CANDIDATE_PATH" ]; then
		return
	fi

	if [ -z "$TARGET_PATHS" ]; then
		TARGET_PATHS="$CANDIDATE_PATH"
	else
		TARGET_PATHS="$TARGET_PATHS,$CANDIDATE_PATH"
	fi
}

add_deny_uid() {
	CANDIDATE_UID="$1"

	case "$CANDIDATE_UID" in
		''|*[!0-9]*)
			return
			;;
	esac

	case ",$DENY_UIDS," in
		*,"$CANDIDATE_UID",*)
			return
			;;
	esac

	if [ -z "$DENY_UIDS" ]; then
		DENY_UIDS="$CANDIDATE_UID"
	else
		DENY_UIDS="$DENY_UIDS,$CANDIDATE_UID"
	fi
}

package_to_uid() {
	PACKAGE_NAME="$1"
	PACKAGE_LINES="$(
		cmd package list packages --user 0 -U "$PACKAGE_NAME" 2>/dev/null || true
		pm list packages --user 0 -U "$PACKAGE_NAME" 2>/dev/null || true
		cmd package list packages -U "$PACKAGE_NAME" 2>/dev/null || true
		pm list packages -U "$PACKAGE_NAME" 2>/dev/null || true
	)"

	printf '%s\n' "$PACKAGE_LINES" |
	while IFS= read -r PACKAGE_LINE; do
		LINE_PKG="${PACKAGE_LINE#package:}"
		LINE_PKG="${LINE_PKG%% uid:*}"
		LINE_UID="${PACKAGE_LINE##* uid:}"
		LINE_UID="${LINE_UID%% *}"

		if [ "$LINE_PKG" = "$PACKAGE_NAME" ] &&
		   [ "$LINE_UID" != "$PACKAGE_LINE" ]; then
			printf '%s\n' "$LINE_UID"
			break
		fi
	done
}

read_deny_uid_config() {
	[ -f "$DENY_UIDS_CONFIG" ] || return

	while IFS= read -r CONFIG_LINE || [ -n "$CONFIG_LINE" ]; do
		CONFIG_LINE="$(printf '%s' "$CONFIG_LINE" | tr -d '\r')"
		case "$CONFIG_LINE" in
			''|\#*)
				continue
				;;
		esac
		OLD_IFS="$IFS"
		IFS=","
		for UID_ITEM in $CONFIG_LINE; do
			IFS="$OLD_IFS"
			UID_ITEM="$(printf '%s' "$UID_ITEM" | tr -d ' ')"
			add_deny_uid "$UID_ITEM"
			IFS=","
		done
		IFS="$OLD_IFS"
	done < "$DENY_UIDS_CONFIG"
}

read_deny_package_config() {
	QUIET="$1"
	UNRESOLVED_PACKAGES=0
	[ -f "$DENY_PACKAGES_CONFIG" ] || return

	while IFS= read -r CONFIG_LINE || [ -n "$CONFIG_LINE" ]; do
		CONFIG_LINE="$(printf '%s' "$CONFIG_LINE" | tr -d '\r ')"
		case "$CONFIG_LINE" in
			''|\#*)
				continue
				;;
		esac
		PACKAGE_UID="$(package_to_uid "$CONFIG_LINE" | head -n 1)"
		if [ -n "$PACKAGE_UID" ]; then
			add_deny_uid "$PACKAGE_UID"
			[ "$QUIET" = "1" ] || log_i "resolved $CONFIG_LINE uid=$PACKAGE_UID"
		else
			UNRESOLVED_PACKAGES=$((UNRESOLVED_PACKAGES + 1))
			[ "$QUIET" = "1" ] || log_i "could not resolve package UID: $CONFIG_LINE"
		fi
	done < "$DENY_PACKAGES_CONFIG"
}

any_target_exists() {
	OLD_IFS="$IFS"
	IFS=","
	for TARGET_ITEM in $TARGET_PATHS; do
		IFS="$OLD_IFS"
		if [ -e "$TARGET_ITEM" ]; then
			return 0
		fi
		IFS=","
	done
	IFS="$OLD_IFS"
	return 1
}

all_targets_exist() {
	OLD_IFS="$IFS"
	IFS=","
	for TARGET_ITEM in $TARGET_PATHS; do
		IFS="$OLD_IFS"
		if [ ! -e "$TARGET_ITEM" ]; then
			return 1
		fi
		IFS=","
	done
	IFS="$OLD_IFS"
	return 0
}

log_missing_targets() {
	OLD_IFS="$IFS"
	IFS=","
	for TARGET_ITEM in $TARGET_PATHS; do
		IFS="$OLD_IFS"
		if [ ! -e "$TARGET_ITEM" ]; then
			log_i "target still missing, kernel will skip: $TARGET_ITEM"
		fi
		IFS=","
	done
	IFS="$OLD_IFS"
}

wait_for_targets() {
	ELAPSED=0

	while [ "$ELAPSED" -lt "$TARGET_WAIT_SECONDS" ]; do
		if all_targets_exist; then
			return 0
		fi
		sleep 1
		ELAPSED=$((ELAPSED + 1))
	done

	log_missing_targets
	any_target_exists
}

wait_for_deny_packages() {
	ELAPSED=0

	while [ "$ELAPSED" -lt "$PACKAGE_WAIT_SECONDS" ]; do
		DENY_UIDS=""
		read_deny_uid_config
		read_deny_package_config 1
		if [ "$UNRESOLVED_PACKAGES" -eq 0 ]; then
			read_deny_package_config 0
			return 0
		fi
		sleep 1
		ELAPSED=$((ELAPSED + 1))
	done

	DENY_UIDS=""
	read_deny_uid_config
	read_deny_package_config 0
}

if [ -f "$CONFIG_PATH" ]; then
	while IFS= read -r CONFIG_LINE || [ -n "$CONFIG_LINE" ]; do
		CONFIG_LINE="$(printf '%s' "$CONFIG_LINE" | tr -d '\r')"
		case "$CONFIG_LINE" in
			''|\#*)
				continue
				;;
		esac
		add_target_path "$CONFIG_LINE"
	done < "$CONFIG_PATH"
fi

if [ -z "$TARGET_PATHS" ]; then
	add_target_path "$DEFAULT_TARGET_PATH"
fi

if [ -f "$HIDE_DIRENTS_CONFIG" ]; then
	HIDE_DIRENTS="$(head -n 1 "$HIDE_DIRENTS_CONFIG" | tr -d '\r')"
fi

if [ -f "$SCOPE_MODE_CONFIG" ]; then
	SCOPE_MODE="$(head -n 1 "$SCOPE_MODE_CONFIG" | tr -d '\r ')"
fi

if [ -f "$TARGET_WAIT_SECONDS_CONFIG" ]; then
	TARGET_WAIT_SECONDS="$(head -n 1 "$TARGET_WAIT_SECONDS_CONFIG" | tr -d '\r ')"
fi

if [ -f "$PACKAGE_WAIT_SECONDS_CONFIG" ]; then
	PACKAGE_WAIT_SECONDS="$(head -n 1 "$PACKAGE_WAIT_SECONDS_CONFIG" | tr -d '\r ')"
fi

if [ -n "$NOHELLO_TARGET_WAIT_SECONDS" ]; then
	TARGET_WAIT_SECONDS="$NOHELLO_TARGET_WAIT_SECONDS"
fi

if [ -n "$NOHELLO_PACKAGE_WAIT_SECONDS" ]; then
	PACKAGE_WAIT_SECONDS="$NOHELLO_PACKAGE_WAIT_SECONDS"
fi

case "$TARGET_WAIT_SECONDS" in
	''|*[!0-9]*)
		TARGET_WAIT_SECONDS=60
		;;
esac

case "$PACKAGE_WAIT_SECONDS" in
	''|*[!0-9]*)
		PACKAGE_WAIT_SECONDS=60
		;;
esac

case "$SCOPE_MODE" in
	deny|global)
		;;
	*)
		log_i "unsupported scope_mode=$SCOPE_MODE, fallback to global"
		SCOPE_MODE=global
		;;
esac

case "$HIDE_DIRENTS" in
	0|false|False|no|No)
		HIDE_DIRENTS=0
		;;
	*)
		HIDE_DIRENTS=1
		;;
esac

if [ -z "$TARGET_PATHS" ]; then
	log_e "empty target path list"
	exit 1
fi

if [ ! -f "$KO_PATH" ]; then
	log_e "missing module: $KO_PATH"
	exit 1
fi

sleep 10

if ! wait_for_targets; then
	log_i "no configured targets exist, skip loading"
	exit 0
fi

if [ "$SCOPE_MODE" = "deny" ]; then
	wait_for_deny_packages
	if [ -z "$DENY_UIDS" ]; then
		log_i "scope_mode=deny but no deny UIDs resolved, skip loading"
		exit 0
	fi
else
	read_deny_uid_config
	read_deny_package_config 0
fi

if grep -q '^nohello ' /proc/modules 2>/dev/null; then
	log_i "nohello is already loaded"
	exit 0
fi

if insmod "$KO_PATH" target_paths="$TARGET_PATHS" hide_dirents="$HIDE_DIRENTS" scope_mode="$SCOPE_MODE" deny_uids="$DENY_UIDS"; then
	log_i "loaded $KO_PATH target_paths=$TARGET_PATHS hide_dirents=$HIDE_DIRENTS scope_mode=$SCOPE_MODE deny_uids=$DENY_UIDS"
else
	log_e "failed to load $KO_PATH"
	exit 1
fi
