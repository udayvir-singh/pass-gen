BIN_DIR=$(HOME)/.local/bin
LIB_DIR=$(HOME)/.local/lib/pass-gen

ifndef VERBOSE
.SILENT:
endif

# ---------------------- #
#          HELP          #
# ---------------------- #
help:
	echo "Usage: make [TARGETS] [VARIABLES]"
	echo
	echo "Targets:"
	echo "  install             install all variants of pass-gen"
	echo "  install-bash        install bash variant of pass-gen"
	echo "  install-lua         build and install lua variant of pass-gen"
	echo "  install-rust        build and install rust variant of pass-gen"
	echo "  uninstall           uninstall all variants of pass-gen"
	echo
	echo "Environment Variables:"
	echo "  VERBOSE             if set, print each command before executing"
	echo "  NOCLEAN             if set, prevent deletion of build artifacts"
	echo
	echo "Examples:"
	echo "  make install"
	echo "  make install-rust NOCLEAN=1"
	echo "  make uninstall"


# ---------------------- #
#        INSTALL         #
# ---------------------- #
install: install-bash install-lua install-rust

wordlist:
	install -D -m 0644 lib/wordlist.txt $(LIB_DIR)/wordlist.txt
	echo :: INSTALLED WORDLIST

install-bash: wordlist
	install -D -m 0755 src/pass-gen.bash $(BIN_DIR)/pass-gen
	echo :: INSTALLED BASH VERSION

install-lua: wordlist
	echo :: BUILDING LUA VERSION
	echo '#!/usr/bin/env lua' > pass-gen-lua
	luac -o - src/pass-gen.lua >> pass-gen-lua
	install -D -m 0755 pass-gen-lua $(BIN_DIR)/pass-gen-lua
ifndef NOCLEAN
	echo :: CLEANING BUILD FILES
	rm -rf pass-gen-lua
endif
	echo :: INSTALLED LUA VERSION

install-rust: wordlist
	echo :: BUILDING RUST VERSION
	cargo build -r
	install -D -m 0755 target/release/pass-gen $(BIN_DIR)/pass-gen-rust
ifndef NOCLEAN
	echo :: CLEANING BUILD FILES
	rm -rf Cargo.lock target
endif
	echo :: INSTALLED RUST VERSION

uninstall:
	rm -rf $(BIN_DIR)/pass-gen \
		$(BIN_DIR)/pass-gen-lua \
		$(BIN_DIR)/pass-gen-rust \
		$(LIB_DIR)
	echo :: UNINSTALLED PASS-GEN
