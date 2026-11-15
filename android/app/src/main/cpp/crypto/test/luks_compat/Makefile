# Host-side differential-test harness for the project's LUKS implementation.
# Compiles the UNMODIFIED production sources (crypto/luks_header.cpp, luks_cipher.cpp, cascade.cpp,
# cipher_shim.cpp, ...) for the host, plus a small CLI (luks_cli.cpp) that the Python suites drive
# side by side with the real `cryptsetup`.
#
#   VC    = checkout of VeraCrypt at the commit pinned in CMakeLists.txt (needs src/Crypto)
#   MBED  = mbedTLS 3.6.x source tree with a built library at $(MBED)/build/library/libmbedcrypto.a
#   needs: libcjson-dev, libssl-dev (libcrypto), g++, gcc
#   make                      -> build/luks_cli
#   make asan                 -> build_asan/luks_cli (AddressSanitizer + UBSan)
SRC  ?= $(abspath $(CURDIR)/../..)/..
VC   ?= $(error set VC=/path/to/VeraCrypt/src)
MBED ?= $(error set MBED=/path/to/mbedtls)
OUT  ?= build
INC  := -Istubs -I$(SRC) -I$(SRC)/Common -I$(SRC)/crypto -I$(VC) -I$(VC)/Crypto -I$(VC)/Crypto/Argon2/include \
        -I$(MBED)/include -I/usr/include/cjson
DEFS := -DCRYPTOPP_DISABLE_ASM -DCRYPTOPP_DISABLE_SSE2 -DCRYPTOPP_DISABLE_SSSE3 -DCRYPTOPP_DISABLE_SHANI \
        -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -DCpuId=VeraCrypt_CpuId
CXXFLAGS := -std=c++20 -O1 -g -fPIC -w $(INC) $(DEFS) $(SANFLAGS)
CFLAGS   := -O1 -g -fPIC -w $(INC) $(DEFS) $(SANFLAGS)
CXXSRCS := $(SRC)/crypto/luks_header.cpp $(SRC)/crypto/cascade.cpp $(SRC)/crypto/cipher_shim.cpp \
           $(SRC)/crypto/user_entropy.cpp $(SRC)/crypto/luks_cipher.cpp
CSRCS := $(VC)/Crypto/Twofish.c $(VC)/Crypto/Serpent.c $(VC)/Crypto/Camellia.c $(VC)/Crypto/kuznyechik.c \
         $(VC)/Crypto/Whirlpool.c $(VC)/Crypto/Streebog.c $(VC)/Crypto/blake2s.c \
         $(VC)/Crypto/Argon2/src/argon2.c $(VC)/Crypto/Argon2/src/ref.c $(VC)/Crypto/Argon2/src/blake2/blake2b.c \
         $(SRC)/Common/Endian.c
OBJS := $(patsubst %.cpp,$(OUT)/%.o,$(notdir $(CXXSRCS))) $(patsubst %.c,$(OUT)/%.o,$(notdir $(CSRCS))) \
        $(OUT)/cpu.o $(OUT)/opt_sse2.o $(OUT)/opt_avx2.o $(OUT)/core.o $(OUT)/thread.o $(OUT)/luks_cli.o
vpath %.cpp $(SRC)/crypto .
vpath %.c $(VC)/Crypto $(VC)/Crypto/Argon2/src $(VC)/Crypto/Argon2/src/blake2 $(SRC)/Common $(SRC)/crypto
$(OUT)/luks_cli: $(OBJS)
	g++ $(SANFLAGS) -o $@ $^ $(MBED)/build/library/libmbedcrypto.a -lcjson -lcrypto -lpthread
$(OUT)/%.o: %.cpp ; @mkdir -p $(OUT) && g++ $(CXXFLAGS) -c $< -o $@
$(OUT)/%.o: %.c ; @mkdir -p $(OUT) && gcc $(CFLAGS) -c $< -o $@
$(OUT)/cpu.o: $(VC)/Crypto/cpu.c ; @mkdir -p $(OUT) && gcc $(CFLAGS) -fgnu89-inline -c $< -o $@
$(OUT)/core.o: $(VC)/Crypto/Argon2/src/core.c ; @mkdir -p $(OUT) && gcc $(CFLAGS) -include $(SRC)/crypto/thread.h -c $< -o $@
$(OUT)/thread.o: $(SRC)/crypto/thread.c ; @mkdir -p $(OUT) && gcc $(CFLAGS) -c $< -o $@
$(OUT)/opt_sse2.o: $(VC)/Crypto/Argon2/src/opt_sse2.c ; @mkdir -p $(OUT) && gcc $(CFLAGS) -msse2 -c $< -o $@
$(OUT)/opt_avx2.o: $(VC)/Crypto/Argon2/src/opt_avx2.c ; @mkdir -p $(OUT) && gcc $(CFLAGS) -mavx2 -c $< -o $@
asan:
	$(MAKE) OUT=build_asan SANFLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer"
.PHONY: asan
