SUDO=sudo
INSTALL_PATH=/usr/local/bin

ifneq ($(INSTALL_LOCAL),)
	SUDO=
	INSTALL_PATH=~/.local/bin
endif

install:
	mkdir -p $(INSTALL_PATH)
	$(SUDO) cp ./network-suite.sh $(INSTALL_PATH)/ns
	chmod +x $(INSTALL_PATH)/ns
