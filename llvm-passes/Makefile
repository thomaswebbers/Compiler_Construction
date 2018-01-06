LLVMCONF ?= llvm-config
CXX     := g++
CFLAGS  := -Wall -Werror -g3 `$(LLVMCONF) --cxxflags` -O0
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S), Darwin)
LDFLAGS := -g3 -shared -Wl,-headerpad_max_install_names -undefined dynamic_lookup `$(LLVMCONF) --ldflags`
else
LDFLAGS := -g3 -shared `$(LLVMCONF) --ldflags`
endif
OBJDIR  ?= ./obj

OBJS    := $(wildcard *.cpp)
OBJS    := $(patsubst %.cpp,$(OBJDIR)/%.o,$(OBJS))

LIB     := libllvm-passes.so


.PHONY: all clean passes check

passes: $(OBJDIR)/$(LIB)

all: passes

check: passes
	@bash tests/run.sh

$(OBJDIR)/$(LIB): $(OBJS)
	$(CXX) $(LDFLAGS) -o $@ $^

$(OBJDIR)/%.o: %.cpp | $(OBJDIR)
	$(CXX) -c $(CFLAGS) -o $@ $<

$(OBJDIR):
	mkdir -p $@

clean:
	rm -rf $(OBJDIR)
