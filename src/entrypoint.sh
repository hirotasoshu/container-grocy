#!/bin/sh
set -eu

version_file="${GROCY_DATAPATH}/.container-grocy-version"

# Initialize the data volume but do not overwrite existing files
cp -anv -t "${GROCY_DATAPATH}" /var/www/data/*

# Clear the viewcache directory
[ -d "${viewcache_path:=${GROCY_DATAPATH}/viewcache}" ] && find "${viewcache_path}" -mindepth 1 -delete

# Perform a DB backup if the Grocy version is upgraded.
if [ -f "${version_file}" ]; then
	old_grocy_version=$(cat "${version_file}")
	case $(apk version -t "${GROCY_VERSION}" "${old_grocy_version}") in
	"<")
		echo "Downgrades are not supported!"
		exit 1
		;;
	">")
		mkdir -p "${backup_path:=${GROCY_DATAPATH}/backups}"
		php <<-EOT
			<?php
			\$db = new SQLite3('${GROCY_DATAPATH}/grocy.db', SQLITE3_OPEN_READONLY);
			\$db->enableExceptions(true);
			\$db->exec( "VACUUM INTO '${backup_path}/grocy-${old_grocy_version}_pre-${GROCY_VERSION}.db';" );
			\$db->close();
		EOT
		# Delete old DB backups except of the previous version.
		find "${backup_path}" -maxdepth 1 -type f -name 'grocy-*_pre-*.db' -and -not -name "*${old_grocy_version}*" -delete
		;;
	esac
fi

# Persist the current grocy version
printf '%s' "${GROCY_VERSION}" >"${version_file}"

# Invoke grocy once to generate or update the grocy.db
# Ensure the www-data user has proper access (php-fpm drops to `www-data` when started as root user)
if [ "$(id -u)" = "0" ]; then
	chown --changes --recursive "www-data:www-data" "${GROCY_DATAPATH}"
	su www-data -s "$(which php)" /var/www/public/index.php
else
	php -f /var/www/public/index.php
fi

# Run to the supplied CMD
exec "$@"
