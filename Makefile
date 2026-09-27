# keel-apache-php: Apache, PHP and Adminer on core, the web half of LAMP and
# LAPP. Compatible with TurnKey Linux appliances: this is what
# turnkeylinux-apps/lamp and turnkeylinux-apps/lapp have in common, built once
# as a layer so both stacks are built on it instead of installing it twice.
#
#     bt-layer apache-php --parent core
#
# Decision 0013 is why this layer exists: a database is a component carried by
# a unit, not a parent layer, so LAMP is apache-php plus the mariadb unit and
# LAPP is apache-php plus the postgresql unit. Before that, a shared web layer
# was impossible, because a stack had to be the child of its database.
#
# What is here is the intersection of the two upstream recipes, and nothing
# either one does not have. README.rst lists what was left to the stacks and
# why: the database, the Adminer configuration that names one
# (conf/adminer-mysql, conf/adminer-pgsql), the confconsole overlay per stack,
# the landing page, and each stack's own extras.

# apache.mk:   overlays/apache, conf apache-vhost apache-headers
#              apache-security apache-ssl
# php.mk:      CONF_VARS PHP_*, overlays/php, conf php
# adminer.mk:  overlays/adminer, conf adminer, and port 12322
# composer.mk: overlays/composer, the two turnkey-composer helpers
include $(FAB_PATH)/common/mk/turnkey/apache.mk
include $(FAB_PATH)/common/mk/turnkey/php.mk
include $(FAB_PATH)/common/mk/turnkey/adminer.mk
include $(FAB_PATH)/common/mk/turnkey/composer.mk

# What lamp.mk and lapp.mk add beyond those four, minus the database half:
#
#   apache-cgi      rewrites serve-cgi-bin.conf to /var/www/cgi-bin, which is
#                   where both stacks put test.cgi
#   adminer-apache  puts Adminer on port 12322 behind Apache, the same for
#                   either database
#   tkl-webcp       the web control panel assets both stacks serve
COMMON_CONF += apache-cgi adminer-apache tkl-webcp
COMMON_OVERLAYS += tkl-webcp

# After the includes, so a file of this overlay wins over a file of the
# shared tree.
COMMON_OVERLAYS += $(CURDIR)/overlay

# 80 and 443 are the stack, 12322 is Adminer, 12321 the panel core carries and
# 12320 the web shell it also carries. The value is the one both upstream
# recipes set, written once here.
WEBMIN_FW_TCP_INCOMING = 22 80 443 12320 12321 12322

include $(FAB_PATH)/common/mk/turnkey.mk
