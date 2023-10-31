INSTALL_PATH=~/.local/bin

ifneq ($(INSTALL_GLOBAL),)
	INSTALL_PATH=/usr/local/bin
endif

install:
	mkdir -p $(INSTALL_PATH)
	cp ./network-suite.sh $(INSTALL_PATH)/ns
	chmod +x $(INSTALL_PATH)/ns
