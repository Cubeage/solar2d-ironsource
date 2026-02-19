# Makefile for iOS static library — libplugin_ironSource.a
# Expects CORONA_ROOT and IRONSOURCE_ROOT to be set by the CI workflow.
# CORONA_ROOT   = path containing CoronaLua.h, CoronaRuntime.h, etc.
# IRONSOURCE_ROOT = path containing IronSource.xcframework

CC      = clang
CFLAGS  = -arch arm64 -isysroot $(SDKROOT) \
          -miphoneos-version-min=12.0 \
          -fobjc-arc \
          -I$(CORONA_ROOT) \
          -F$(IRONSOURCE_ROOT) \
          -DNDEBUG -Os

SDKROOT = $(shell xcrun --sdk iphoneos --show-sdk-path)

SRC     = plugin_ironSource.mm
OBJ     = plugin_ironSource.o
LIB     = libplugin_ironSource.a

all: $(LIB)

$(OBJ): $(SRC)
	$(CC) $(CFLAGS) -c -o $@ $<

$(LIB): $(OBJ)
	ar rcs $@ $^
	ranlib $@

clean:
	rm -f $(OBJ) $(LIB)

.PHONY: all clean
