CFLAGS :=
LDFLAGS :=

.PHONY: all check clean
.SUFFIXES:

all:

%: %.o
	clang -o $@ $< $(LDFLAGS)

%.o: %.ll
	llc -filetype=obj -o $@ $<

%.ll: %.fc
	frontend $(CFLAGS) -o $@ $<

check:
	@python runtests.py

clean:
	rm -rf parsetab.py parser.out __pychache__ test/tmp*
