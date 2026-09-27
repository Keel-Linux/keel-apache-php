#!/bin/bash
# Boot test of this layer (org-plan section 1), modelled on the ones in
# keel-nodebb, keel-mariadb and keel-postgresql: assemble the published layer
# chain into an LXC rootfs, boot it headless from tests/instance.yaml, wait for
# the first boot to finish, then ask the machine for what the layer is for.
#
# What it proves, all of it over the container's global IPv6 address, because
# IPv6 first is the default this project builds for and a test written against
# 127.0.0.1 would pass on a layer that answers only on IPv4:
#
#   Apache answers on 80 and on 443 for a page the overlay ships,
#   PHP executes, rather than the page coming back as source text,
#   the CGI handler runs the Perl script under /var/www/cgi-bin,
#   Adminer answers on its own port, 12322,
#   the Webmin module for Apache is installed and Webmin answers on 12321,
#   and keel diff reports no drift against the description that was declared.
#
# Called by the reusable workflow test-appliance.yml after keel pull and
# keel verify; runnable by hand as root on any host with LXC, see
# tests/README.md. It builds nothing: the layers come from the mirror or
# from a directory bt-layer wrote, so the test needs no fab, deck or
# buildtasks. The logic lives in tests/lib/boot-test-lib.sh and is unit
# tested; this file is the thin main that touches the system.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/boot-test-lib.sh
source "$here/lib/boot-test-lib.sh"

bt_parse_args "$@" || { rc=$?; [ "$rc" -eq 2 ] && exit 0; exit 1; }
BT_SPEC=${BT_SPEC:-$here/instance.yaml}
if [ "$(id -u)" -ne 0 ]; then
    echo "boot-test: must run as root (keel assemble, lxc-start)" >&2
    exit 1
fi
for tool in keel lxc-start lxc-info lxc-attach lxc-stop curl; do
    command -v "$tool" >/dev/null || { echo "boot-test: $tool not found" >&2; exit 1; }
done

container_dir=$BT_LXC_PATH/$BT_NAME
log() { printf '%s boot-test: %s\n' "$(date -u +%H:%M:%S)" "$*"; }
lxc() { "lxc-$1" -P "$BT_LXC_PATH" -n "$BT_NAME" "${@:2}"; }

cleanup() {
    local rc=$?
    if [ "$rc" -ne 0 ] && [ -r "$BT_ROOTFS/var/log/inithooks.log" ]; then
        log "last lines of the container's inithooks log:"
        tail -n 40 "$BT_ROOTFS/var/log/inithooks.log"
    fi
    if [ "$BT_KEEP" -eq 1 ]; then
        log "keeping $BT_NAME under $BT_LXC_PATH (--keep); lxc-attach -P $BT_LXC_PATH -n $BT_NAME"
        return
    fi
    lxc stop -k >/dev/null 2>&1 || true
    rm -rf "$container_dir"
}
trap cleanup EXIT

# 1. Assemble the chain from the layers the build host published.
log "assembling $BT_APPLIANCE from $BT_LAYERS_DIR into $BT_ROOTFS"
lxc stop -k >/dev/null 2>&1 || true
rm -rf "$container_dir"
mkdir -p "$BT_ROOTFS"
keel pull "$BT_APPLIANCE" --source "$BT_LAYERS_DIR" --cache-dir "$BT_CACHE_DIR" --non-interactive
keel assemble "$BT_APPLIANCE" --rootfs "$BT_ROOTFS" --cache-dir "$BT_CACHE_DIR" --non-interactive

# 2. The container marks, the instance description, the secrets it
#    references and the conf the first boot hooks read. bt_mark_container
#    does what buildtasks' container patch does: the marker under
#    /var/lib/turnkey-info that inspect reads to call the machine a
#    container (managed_by: host), and REDIRECT_OUTPUT=true with a
#    drop-in, without which a hook that prints a lot blocks writing to a
#    tty1 nobody reads. The conf is what makes the first boot headless,
#    and without it 30rootpass waits on a dialog forever.
log "installing the description, the secrets and the conf into $BT_ROOTFS"
bt_mark_container "$BT_ROOTFS"
install -d -m 0700 "$BT_ROOTFS/etc/keel/secrets"
for target in $(bt_secret_targets "$BT_ROOTFS"); do
    bt_random_password > "$target"
    chmod 0600 "$target"
done
for target in $(bt_spec_targets "$BT_ROOTFS"); do
    install -D -m 0600 "$BT_SPEC" "$target"
done
bt_spec_in_rootfs "$BT_SPEC" "$BT_ROOTFS" > "$container_dir/instance-host.yaml"
keel spec apply --spec "$container_dir/instance-host.yaml" \
    --conf "$BT_ROOTFS/etc/inithooks.conf" --non-interactive

# 3. Boot.
bt_lxc_config "$BT_NAME" "$BT_ROOTFS" "$BT_BRIDGE" > "$container_dir/config"
log "starting $BT_NAME on bridge $BT_BRIDGE"
lxc start -d

# 4. A global IPv6 address from the bridge.
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" "a global IPv6 address on $BT_NAME" \
    bt_container_ipv6 "$BT_NAME" "$BT_LXC_PATH" > /dev/null
addr=$(bt_container_ipv6 "$BT_NAME" "$BT_LXC_PATH")
log "container address $addr"

# 5. First boot finished: 98finalize has cleared RUN_FIRSTBOOT and the
#    machine answers, on the console (confconsole's usage screen) or on
#    SSH. The answer alone is not enough: sshd is up long before the hooks
#    are done, so the flag is what says the first boot ended.
usage_screen() {
    lxc attach -- pgrep -f confconsole > /dev/null 2>&1
}
ssh_answers() {
    local banner
    banner=$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1" && read -r -t 5 line <&3 && printf "%s" "$line"' \
        "$addr" "$BT_SSH_PORT" 2>/dev/null) || return 1
    bt_is_ssh_banner "$banner"
}
first_boot_done() {
    bt_firstboot_done_in "$BT_ROOTFS/etc/default/inithooks" || return 1
    usage_screen || ssh_answers
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" "the first boot of $BT_NAME to finish" \
    first_boot_done
log "first boot finished; ssh root@$addr"

# 6. Apache answers over IPv6, on both ports, for a page this layer ships.
#    The request is made from the host to the container's global address, so
#    what is proved is a machine on the network and not a socket on loopback.
http_code() {
    curl -6 -k -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" || true
}
http_body() {
    curl -6 -k -s --max-time 10 "$1" || true
}

code=""
php_over_http() {
    code=$(http_code "http://[$addr]:$BT_HTTP_PORT$BT_PHP_PROBE_PATH")
    [ "$code" = "$BT_HTTP_OK" ]
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" \
    "apache on http://[$addr]:$BT_HTTP_PORT$BT_PHP_PROBE_PATH" php_over_http
bt_http_verdict "$code" "$BT_HTTP_PORT" "apache"

code=$(http_code "https://[$addr]:$BT_HTTPS_PORT$BT_PHP_PROBE_PATH")
bt_http_verdict "$code" "$BT_HTTPS_PORT" "apache over TLS"

# 7. PHP executed. The page is one line of PHP, so the report in the body is
#    the proof, and the source text in the body is the failure that matters
#    most: a web stack that serves PHP as a file publishes what its pages
#    contain. Both ports are asked, because mod_php is per server and the TLS
#    vhost is a second one.
bt_php_verdict "$(http_body "http://[$addr]:$BT_HTTP_PORT$BT_PHP_PROBE_PATH")"
bt_php_verdict "$(http_body "https://[$addr]:$BT_HTTPS_PORT$BT_PHP_PROBE_PATH")"

# 8. The CGI handler runs the script under /var/www/cgi-bin, which is where
#    common/conf/apache-cgi points serve-cgi-bin.conf and where the overlay
#    puts test.cgi.
code=$(http_code "http://[$addr]:$BT_HTTP_PORT$BT_CGI_PROBE_PATH")
bt_http_verdict "$code" "$BT_HTTP_PORT" "the CGI script"
bt_cgi_verdict "$(http_body "http://[$addr]:$BT_HTTP_PORT$BT_CGI_PROBE_PATH")"

# 8b. Adminer answers on its own port. It is part of both stacks, so it is
#     part of this layer; which database it is pointed at is not, and is set by
#     the stack (common/conf/adminer-mysql, common/conf/adminer-pgsql).
adminer_answers() {
    code=$(http_code "http://[$addr]:$BT_ADMINER_PORT/")
    [ "$code" = "$BT_HTTP_OK" ]
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" \
    "adminer on http://[$addr]:$BT_ADMINER_PORT/" adminer_answers
bt_http_verdict "$code" "$BT_ADMINER_PORT" "adminer"

# 8c. The panel core carries, with the module this layer adds to it.
status=$(lxc attach -- dpkg-query -W -f '${Status}' "$BT_WEBMIN_MODULE" 2>/dev/null || true)
bt_module_verdict "$BT_WEBMIN_MODULE" "$status"
webmin_answers() {
    code=$(http_code "https://[$addr]:$BT_WEBMIN_PORT/")
    [ "$code" = 200 ] || [ "$code" = 401 ]
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" "webmin on https://[$addr]:$BT_WEBMIN_PORT/" \
    webmin_answers
bt_webmin_verdict "$code"

# 9. No drift between the declared description and the booted root.
set +e
keel diff --root "$BT_ROOTFS" --spec "$BT_SPEC"
code=$?
set -e
bt_diff_verdict "$code"
log "$BT_APPLIANCE boot test passed"
