#!/bin/sh

set -e

readonly _DOCKER_RW_DIR="/build-rw"
readonly _DOCKER_RO_DIR="/build-ro"
readonly _DOCKER_TMP_DIR="/build-tmp"
readonly _IMG_NAME="httpd-build"

readonly _HTTPD_TAR="httpd-2.4.41.tar.gz"
readonly _HTTPD_APR_TAR="apr-1.7.0.tar.gz"
readonly _HTTPD_APU_TAR="apr-util-1.6.1.tar.gz"

inside_docker() {
	local nr_cpus
	local nr_threads
	local httpd_root_dir
	local apr_root_dir
	local apu_root_dir

	nr_cpus="$(grep -c '^processor' /proc/cpuinfo)"
	if test "$nr_cpus" -gt "1"; then
		nr_threads="$(($nr_cpus >> 1))"
	else
		nr_threads="$nr_cpus"
	fi

	find "$_DOCKER_RW_DIR" -mindepth 1 -maxdepth 1 -exec 'rm' '-r' '{}' \;

	httpd_root_dir="${_HTTPD_TAR%*.tar.*}"
	apr_root_dir="${_HTTPD_APR_TAR%*.tar.*}"
	apu_root_dir="${_HTTPD_APU_TAR%*.tar.*}"

	cd "$_DOCKER_RW_DIR"
	tar -x -f "${_DOCKER_RO_DIR}/${_HTTPD_TAR}"
	mv "$httpd_root_dir" "httpd"
	cd "httpd"
	patch -p1 < "${_DOCKER_RO_DIR}/httpd-cpp.patch"

	cd "srclib"
	tar -x -f "${_DOCKER_RO_DIR}/${_HTTPD_APR_TAR}"
	mv "$apr_root_dir" "apr"
	cd "apr"
	patch -p1 < "${_DOCKER_RO_DIR}/apr-cpp.patch"

	cd ".."
	tar -x -f "${_DOCKER_RO_DIR}/${_HTTPD_APU_TAR}"
	mv "$apu_root_dir" "apr-util"

	cd ".."
	./configure --prefix="${_DOCKER_RW_DIR}/usr/apache2"          \
	            --oldincludedir="${_DOCKER_RW_DIR}/usr/include"   \
	            --enable-pie                                      \
	            --enable-modules="reallyall"
	make "-j${nr_threads}"
	make install

	return 0
}

if test "$$" -eq "1"; then
	inside_docker
	exit "$?"
fi

_SHOULD_PRUNE="0"

while getopts ":p" _OPT; do
	case "$_OPT" in
	p)
		if test "$(docker images -q "$_IMG_NAME")" != ""; then
			_SHOULD_PRUNE="1"
		fi
		;;
	*)
		printf "Unknown option: %s\n" "$OPTARG"
		exit 1
		;;
	esac
done

_ROOT_DIR="$(realpath "$(dirname "$0")/..")"
_RO_DIR="${_ROOT_DIR}/ro-data.d"
_RW_DIR="${_ROOT_DIR}/rw-data.d"
_FILENAME="$(basename "$0")"

if test "$_SHOULD_PRUNE" -eq "1"; then
	docker rmi -f "$_IMG_NAME"
fi

if test "$(docker images -q "$_IMG_NAME")" = ""; then
	docker build -t "$_IMG_NAME" "$_ROOT_DIR"
fi

docker run                                                                                   \
       --mount type=bind,src="$_RO_DIR",dst="$_DOCKER_RO_DIR",ro=true,bind-nonrecursive=true \
       --mount type=bind,src="$_RW_DIR",dst="$_DOCKER_RW_DIR",bind-nonrecursive=true         \
       --mount type=tmpfs,dst="$_DOCKER_TMP_DIR",tmpfs-size=1G                               \
       -h "${_IMG_NAME}.local" "$_IMG_NAME" "${_DOCKER_RO_DIR}/${_FILENAME}"

exit 0
