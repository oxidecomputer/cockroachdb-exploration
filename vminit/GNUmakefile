#
# This is an extremely janky Makefile for building the various vminit tarballs.
# It doesn't have proper dependencies or anything.
#

all: vminit-common.tgz vminit-cockroachdb.tgz vminit-mon.tgz

vminit-common.tgz:
	(cd common && tar czf ../$@ .)

vminit-cockroachdb.tgz:
	(cd cockroachdb && tar czf ../$@ .)

vminit-mon.tgz:
	(cd mon && tar czf ../$@ .)
