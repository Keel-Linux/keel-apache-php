# Coverage

Standard: decisions 0003 (90 percent per repository, 95 for code the project
writes) and 0004 (bats plus kcov for shell; a build and a boot on LXC as the
acceptance test of a recipe, docs/org-plan.md section 1).

## Measured 2026-09-27

| File | Test | Lines | Note |
| --- | --- | --- | --- |
| tests/lib/boot-test-lib.sh | tests/boot-test.bats (45 tests) | 100 percent (177/177) under kcov | argument parsing, address discovery, deadlines, the container marks, the spec and secret paths, and the HTTP, PHP, CGI, Adminer, Webmin, module and diff verdicts |
| conf.d/main | the build | integration only | build time script, 0004 pragmatic limits; every line of it is a check on what the shared conf scripts left behind, so a failed build names the thing that is wrong |
| tests/boot-test.sh | itself | integration only | the thin main of the acceptance test: keel and LXC as root |

Total: **100 percent (177/177)**, 45 bats tests. `tests/coverage.sh` fails
below `COVERAGE_THRESHOLD`, which the workflow sets to 100, the measured
number. It is only ever raised (decision 0006).

    $ COVERAGE_THRESHOLD=100 tests/coverage.sh
    kcov line coverage (threshold 100 percent):
     100.00  177/177  boot-test-lib.sh

This layer ships no first boot hook and no library of its own, which is why one
file is measured: it installs and configures software and leaves the
declarative surface to the appliance above it. What the layer does at build
time is checked by `conf.d/main` (ports, enabled modules, the sites in force,
PHP on the command line) and what it does on a running machine is checked by
the boot test.

## The fourth copy of the boot test library, and what to do about it

`tests/lib/boot-test-lib.sh` now exists in keel-core, keel-nodebb,
keel-mariadb, keel-postgresql and here. About 130 of its 177 lines are
identical in all five; what differs is the verdicts of the appliance. The
STATUS entry of 2026-09-27 said the shared half should move into
`keel-linux/.github`, which already holds the reusable workflows and
`bin/require-changelog` with its own gate, at the fourth caller. This is that
caller.

It was not done in the same change as this layer on purpose: it touches five
repositories, two of which have work in flight, and it puts test logic behind
the same `@main` reference as the workflows, which the audit of 2026-09-26
called the highest blast radius in the organization. It is the next thing to
do in that repository, before LAMP and LAPP add a sixth and seventh copy.

## The appliance gate

`appliance / build-and-boot` runs through the organization's
`test-appliance.yml` on the self-hosted `keel-lxc` runner, which fetches the
published layer from `https://mirror.keellinux.org/layers`, verifies it,
assembles it, boots it in LXC and runs `tests/boot-test.sh`. Nothing is built
there. While the layer is not published the job skips with a notice, so the
check exists and `main` can require it from the first day.

## Plan

- Publish the layer, then require `appliance / build-and-boot` on `main`.
- Move the shared half of the boot test library into `keel-linux/.github`, with
  its own gate there, and leave each appliance its verdicts.
- Measure `conf.d/main` if it ever grows a decision. Today every line is an
  assertion, which the build itself exercises.
