# Tests

    bats tests/boot-test.bats                     the logic of the boot test
    COVERAGE_THRESHOLD=100 tests/coverage.sh      the gate, kcov over bats
    sudo tests/boot-test.sh apache-php            the boot test itself, as root

`boot-test.bats` covers `tests/lib/boot-test-lib.sh`: argument parsing, the
address discovery from `lxc-info`, the deadlines, the container marks, the spec
and secret paths, and every verdict. Nothing needs root, a network, a web
server or LXC.

`boot-test.sh` is the thin main that touches the system. It assembles the
published layer chain into an LXC rootfs, boots it headless from
`tests/instance.yaml`, and then, over the container's global IPv6 address:

- asks for `/phpinfo.php` on 80 and on 443, and fails unless both answer 200;
- checks that the body carries the PHP report and not the page's source, so a
  stack that serves PHP as text fails rather than passes;
- asks for `/cgi-bin/test.cgi` and checks the script's output, not its source;
- asks Adminer on 12322, over TLS, because that vhost is TLS only, and checks
  that the page is Adminer's own;
- checks that `webmin-apache` is installed and that Webmin answers on 12321;
- runs `keel diff` against the description that was declared.

It builds nothing: the layers come from the mirror or from a directory
`bt-layer` wrote, so `--layers-dir` is how it is run on the build host before a
layer is published.
