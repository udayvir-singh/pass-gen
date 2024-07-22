PREFIX   ?= ${HOME}/.local
BIN_DIR  ?= $(PREFIX)/bin
DATA_DIR ?= $(PREFIX)/share/pass-gen
MAN_DIR  ?= $(PREFIX)/share/man/man1

ifndef VERBOSE
.SILENT:
endif

.ONESHELL:

# ---------------------- #
#          HELP          #
# ---------------------- #
help:
	echo 'Usage: make [VARIABLES] TARGET'
	echo
	echo 'Targets:'
	echo '  install    Install pass-gen on this system'
	echo '  uninstall  Uninstall pass-gen from this system'
	echo '  help       Print this help message and exit'
	echo
	echo 'Environment Variables:'
	echo '  PREFIX     Prefix for installation paths    (default: $$HOME/.local)'
	echo '  BIN_DIR    Directory for executables        (default: $$PREFIX/bin)'
	echo '  DATA_DIR   Directory for data files         (default: $$PREFIX/share/pass-gen)'
	echo '  MAN_DIR    Directory for manual pages       (default: $$PREFIX/share/man/man1)'
	echo '  VERBOSE    Enable verbose command execution (default: unset)'
	echo
	echo 'Examples:'
	echo '  make install'
	echo '  sudo make PREFIX=/usr install'


# ---------------------- #
#        INSTALL         #
# ---------------------- #
install:
	echo :: INSTALLING PASSWORD GENERATOR
	$(call install, 0755, ./pass-gen.bash, $(BIN_DIR)/pass-gen)
	$(call install, 0755, ./pass-genf.bash, $(BIN_DIR)/pass-genf)
	$(call install, 0644, ./pass-gen.1, $(MAN_DIR)/pass-gen.1)
	$(call install, 0644, ./pass-genf.1, $(MAN_DIR)/pass-genf.1)
	for DATASET in ./datasets/*; do
	$(call install, 0644, $$DATASET, $(DATA_DIR)/$${DATASET##*/})
	done
	echo :: DONE

uninstall:
	echo :: UNINSTALLING PASSWORD GENERATOR
	$(call remove, $(BIN_DIR)/pass-gen)
	$(call remove, $(BIN_DIR)/pass-genf)
	$(call remove, $(MAN_DIR)/pass-gen.1)
	$(call remove, $(MAN_DIR)/pass-genf.1)
	for DATASET in ./datasets/*; do
	$(call remove, $(DATA_DIR)/$${DATASET##*/})
	done
	echo :: DONE


# ----------------------- #
#          UTILS          #
# ----------------------- #
define success
	echo -e "  \e[1;32m==>\e[0m"
endef

define failure
	echo -e "  \e[1;31m==>\e[0m"
endef

define install
	TMP_FILE=$$(mktemp)
	if install -Dm $(1) $(2) $(3) 2>$$TMP_FILE; then
		$(success) $(2)
	else
		$(failure) $(2)
		sed "s/^/      /" $$TMP_FILE
	fi
	rm $$TMP_FILE
endef

define remove
	TMP_FILE=$$(mktemp)
	if rm $(1) 2>$$TMP_FILE; then
		$(success) $(1)
	else
		$(failure) $(1)
		sed "s/^/      /" $$TMP_FILE
	fi
	rm $$TMP_FILE
endef