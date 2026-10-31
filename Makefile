CC = cc
CFLAGS ?= -O2 -fPIE -Wall -Wextra -Werror
ASFLAGS = -Wa,--fatal-warnings
LDFLAGS ?= -pie -Wl,-z,relro,-z,now,-z,noexecstack
PREFIX ?= /usr/local

.PHONY: all clean test install
all: build/temporion-x86d
build:
	mkdir -p $@
build/temporion-x86d: asm/temporion-x86d.S | build
	$(CC) $(ASFLAGS) $(LDFLAGS) -o $@ $< -ldl
build/temporion-x86.o: asm/temporion-x86d.S | build
	$(CC) $(ASFLAGS) -DTEMPORION_X86_NO_MAIN -c -o $@ $<
install: build/temporion-x86d
	install -Dm755 $< $(DESTDIR)$(PREFIX)/bin/temporion-x86d
clean:
	rm -rf build

build/unit: tests/unit.c build/temporion-x86.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ -ldl
build/redirect.so: tests/redirect.c | build
	$(CC) $(CFLAGS) -fPIC -shared -o $@ $< -ldl
build/libnvidia-ml.so.1: tests/nvml.c | build
	$(CC) $(CFLAGS) -fPIC -shared -o $@ $<
test: all build/unit build/redirect.so build/libnvidia-ml.so.1 build/missing/libnvidia-ml.so.1
	build/unit
	python3 tests/identity.py
	python3 tests/integration.py

build/bench-assembly: bench/assembly.c build/temporion-x86.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ -ldl

build/probe: tests/probe.c build/temporion-x86.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ -ldl
build/oracle: tests/oracle.rs | build
	rustc --edition=2021 -O -o $@ $<
.PHONY: differential bench-build
differential: build/probe build/oracle
	python3 tests/differential.py
bench-build: all build/bench-assembly build/redirect.so build/libnvidia-ml.so.1
	cargo build --release
	rustc --edition=2021 -A dead_code -C opt-level=s -C lto -C codegen-units=1 -C panic=abort -C strip=symbols bench/rust.rs -o build/bench-rust-size
	rustc --edition=2021 -A dead_code -C opt-level=3 -C lto -C codegen-units=1 -C panic=abort -C strip=symbols bench/rust.rs -o build/bench-rust-speed
	rustc --edition=2021 -C opt-level=3 -C lto -C codegen-units=1 -C panic=abort -C strip=symbols src/main.rs -o build/temporion-x86d-rust-speed

build/missing/libnvidia-ml.so.1: tests/nvml.c | build
	mkdir -p build/missing
	$(CC) $(CFLAGS) -fPIC -shared -DTEMPORION_X86_TEST_OMIT_TEMP -o $@ $<
