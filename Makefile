# Makefile — checks that can run without touching the target machine.
#
#   make check      shell syntax + config sanity (safe anywhere)
#   make st         build st on the OpenBSD target
#   make install    run the staged installer (needs root on OpenBSD)

.PHONY: check lint validate st install clean

check: lint validate

lint:
	@set -e; for f in install.sh provision.sh validate.sh lib/common.sh \
		lib/stages/*.sh share/st/build.sh home/bin/* \
		home/.config/spectrwm/bar.sh home/.config/lf/open \
		home/.config/lf/preview home/.xsession home/.xinitrc \
		etc/apm/suspend; do \
		sh -n "$$f"; \
	done; echo "shell: ok"

validate:
	@sh validate.sh

st:
	@sh share/st/build.sh

install:
	@sh ./install.sh --metal

clean:
	rm -f *~ home/bin/*~ 2>/dev/null || true
