#
# Dreamcast Linux Makefile
# Author: Anders Evenrud <andersevenrud@gmail.com>
#

all: base dreamcast

base:
	(cd dreamcast && docker build -t dreamcastlinux:distro .)

dreamcast:
	(docker run --privileged -it \
		-v "${PWD}/.dreamcast/src:/usr/src/dreamcast" \
		-v "${PWD}/.dreamcast/opt:/opt/dreamcast" \
		-v "${PWD}/build:/opt/build" \
		dreamcastlinux:distro)

clean:
	sudo rm -rf .dreamcast

.PHONY: base dreamcast clean
