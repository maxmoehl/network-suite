SUDO=sudo
INSTALL_PATH=/usr/local/bin

ifneq ($(INSTALL_LOCAL),)
	SUDO=
	INSTALL_PATH=~/.local/bin
endif

install:
	$(SUDO) mkdir -p $(INSTALL_PATH)
	$(SUDO) cp ./network-suite.sh $(INSTALL_PATH)/ns
	$(SUDO) chmod +x $(INSTALL_PATH)/ns
