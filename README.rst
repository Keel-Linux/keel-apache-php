.. warning::

   **Archived (2026-10-07).** Keel retired Apache: web appliances use nginx
   with php-fpm (LEMP), see Keel-Linux/keel-nginx-php-fastcgi and Keel-Linux/keel-web.
   This repository is kept read-only for reference.

keel-apache-php
===============

Apache, PHP and Adminer on ``core``: the web half of LAMP and LAPP, built once
as a layer both stacks are built on. Compatible with TurnKey Linux appliances,
and corresponding to what `turnkeylinux-apps/lamp
<https://github.com/turnkeylinux-apps/lamp>`_ and `turnkeylinux-apps/lapp
<https://github.com/turnkeylinux-apps/lapp>`_ have in common::

    bt-layer apache-php --parent core

Why it can exist now
--------------------

Upstream each stack installs its own web server, because each stack is built
around its own database. Decision 0013 turned the database into a component
carried by a fab unit instead of a parent layer, and that is what frees the web
half to be shared::

    core
      apache-php
        lamp   = apache-php + unit.d/mariadb
        lapp   = apache-php + unit.d/postgresql
      mariadb  = core + unit.d/mariadb
      postgresql = core + unit.d/postgresql

So this layer is the second consumer decision 0010 was waiting for: the reason
the unit mechanism was built is that LAMP and LAPP can now share this.

What is in it
-------------

======================================  ====================================
``Makefile``                            ``apache.mk``, ``php.mk``, ``adminer.mk`` and ``composer.mk`` of ``common``, the shared conf scripts, this overlay, the firewall ports
``plan/main``                           apache2, libapache2-mod-php, php-cli, mod_security2, mod_evasive, mod_perl2, webmin-apache, webmin-phpini, adminer, libjs-jush, composer
``conf.d/main``                         mod_cgi enabled, the webcp icon set, and the checks that the ports, modules and sites are in force
``overlay/etc/apache2/``                the default site serving ``/var/www`` on 80 and 443, and ``status.conf``
``overlay/var/www/``                    ``phpinfo.php`` and ``cgi-bin/test.cgi``, the two pages both stacks ship and the boot test asks for
``keel/instance.example.yaml``          the instance description an operator starts from
``tests/``                              bats for the boot test's logic, ``boot-test.sh`` for the machine
======================================  ====================================

Webmin comes from ``core`` and answers on 12321; this layer adds
``webmin-apache`` and ``webmin-phpini``, the two modules that put a web stack
in it. Adminer answers on 12322, which ``common/conf/adminer-apache`` puts
behind Apache, and only over TLS: the vhost of the shared tree opens with
``SSLEngine on``, so a plain HTTP request on that port is answered 400 by
Apache and not by Adminer. The boot test found that on its first run and now
asks for ``https://``.

What it deliberately leaves out
-------------------------------

The rule this layer is built to is "what LAMP and LAPP both need, and nothing
either one does not". So the intersection is here and the difference is not:

- **the database.** It arrives as a unit in the stack:
  ``unit.d/mariadb`` for LAMP, ``unit.d/postgresql`` for LAPP.
- **the Adminer configuration that names a database.**
  ``common/conf/adminer-mysql`` creates an Adminer account in MariaDB and
  enables the hook that resets it; ``common/conf/adminer-pgsql`` points Adminer
  at the ``pgsql`` driver. Adminer itself, its CSS, its Apache site and its log
  directory are here, because those are the same either way.
- **the landing page.** Upstream's ``/var/www/index.php`` says "TurnKey LAMP"
  or "TurnKey LAPP"; it belongs to the stack. What is here is the document root
  that serves it.
- **the confconsole overlay**, ``confconsole-lamp`` and ``confconsole-lapp``,
  one file each, per stack.
- **each stack's extras:** ``php-xdebug`` and ``php-pear`` and the Python and
  Perl MySQL drivers in LAMP, the Python and Perl PostgreSQL drivers in LAPP.
- **LAMP's ``Header always unset Upgrade``**, which it also carries as
  ``conf-available/remove-upgrade-header.conf``, so it is LAMP's and not the
  stack's.

Two things in it are worth naming out loud
------------------------------------------

``/var/www/phpinfo.php`` is one line of PHP that publishes the interpreter's
whole configuration to anybody who asks for it. Both upstream stacks ship it on
port 80, so it is here, and the boot test uses it as the proof that PHP
executes. Whether an appliance should ship it at all is a question for the
project rather than for this layer, and the day the answer is no, this is the
one file to remove and the boot test gets a probe page of its own.

``/var/www/`` is served with ``Options Indexes``, as both stacks serve it, so a
directory with no index file is listed. The stacks put a landing page there.

Tests
-----

``tests/README.md`` has the detail. In short: ``tests/coverage.sh`` runs the
bats suite under kcov and gates the shell this layer writes, and
``tests/boot-test.sh`` assembles the layer, boots it headless in LXC, and over
the container's global IPv6 address proves that Apache answers on 80 and 443,
that PHP executes rather than being served as source, that the CGI handler
runs, that Adminer answers on 12322 over TLS with its own page, that
``webmin-apache`` is installed and Webmin answers on 12321, and that
``keel diff`` reports no drift.