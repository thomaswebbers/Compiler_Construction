# Distribution of code to students
DIST_FILE     := coco
DIST_DIR      := coco
DIST_BRANCH   := dist
DIST_ADDFILES := doc/langref.pdf

.PHONY: all
all: deps passes

# dependencies

.PHONY: deps
deps: lib/.bootstrapped
	@if ! which frontend; then \
		echo "PATH incorrect - make sure the virtualenv is activated!"; \
		echo "Run 'source shrc' and try running make again"; \
		exit 1; \
	fi

lib/.bootstrapped: | bootstrap.sh
	bash bootstrap.sh
	touch $@

# LLVM passes

.PHONY: passes
passes: deps
	make -C llvm-passes

# Runtime with helper functions

.PHONY: runtime
runtime: deps
	make -C runtime

# tests

.PHONY: check-frontend check-passes
check-frontend: deps
	make -C frontend check

check-passes: passes runtime
	make -C llvm-passes check

# full program examples

.PHONY: examples example-%
examples: passes runtime
	make -BC examples

example-%: passes runtime
	make -BC examples bin/$*

# cleanup

.PHONY: clean
clean:
	rm -f bootstrap.log $(DIST_FILE).tar.gz
	make -C llvm-passes clean
	make -C runtime clean
	make -C examples clean

.PHONY: cleaner
cleaner: clean
	rm -rf lib
	rm handin-1.tar.gz handin-2.tar.gz handin-3.tar.gz

.PHONY: handin-1 handin-2 handin-3

handin-1:
	echo "Creating tarball for assignment 1"
	tar -cvz --exclude='__pycache__' --exclude='*.pyc' -f handin-1.tar.gz frontend

handin-2:
	echo "Creating tarball for assignment 2"
	tar -cvz --exclude='*.o' --exclude='obj/' -f handin-2.tar.gz llvm-passes

handin-3:
	echo "Creating tarball for assignment 3"
	tar -cvz --exclude='*.o' --exclude='obj/' -f handin-3.tar.gz llvm-passes runtime
