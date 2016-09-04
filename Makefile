# Makefile for CCAN

# Adding 'quiet=1' to make arguments builds silently
QUIETEN.1 := @
PRE := $(QUIETEN.$(quiet))

# Adding 'opt=1' to make arguments builds optimised
OPT.1 := -O2
OPT_CFAGS := $(OPT.$(opt))

default: all

# Avoid some work when cleaning
CLEANING := $(if $(filter clean, $(MAKECMDGOALS)),true,false)

# Our flags for building
WARN_CFLAGS := -Wall -W -Wstrict-prototypes -Wold-style-definition \
 -Wmissing-prototypes -Wmissing-declarations -Wpointer-arith \
 -Wwrite-strings -Wundef -Wno-unknown-pragmas -Wno-unused-parameter \
 -Wno-missing-field-initializers
DEPENDENCY_FLAGS = -MMD -MP -MF$(@:%=%.d) -MT$@
CCAN_CFLAGS := $(OPT_CFAGS) -g3 -ggdb $(WARN_CFLAGS) -DCCAN_STR_DEBUG=1 -I. $(CFLAGS)

# Anything with an _info file is a module ...
INFO_SRCS := $(wildcard ccan/*/_info ccan/*/*/_info)
ALL_INFOS := $(INFO_SRCS:%_info=%info)
ALL_MODULES := $(ALL_INFOS:%/info=%)

# ... Except stuff that needs external dependencies, which we exclude
MODULES_EXCLUDE := altstack generator jmap jset nfs ogg_to_pcm tal/talloc wwviaudio
MODULES:= $(filter-out $(MODULES_EXCLUDE:%=ccan/%) ,$(ALL_MODULES))

# Sources are C files in each module, objects the resulting .o files
SRCS := $(wildcard $(MODULES:%=%/*.c))
OBJS := $(SRCS:%.c=%.o)
DEPS := $(OBJS:%=%.d)

# We build all object files using our CCAN_CFLAGS, after config.h
%.o : %.c config.h
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEPENDENCY_FLAGS) -c $< -o $@

# Our static library is made from all object files
LIB := libccan.a
$(LIB): $(OBJS)
	$(PRE)$(AR) -rs $@ $^

# _info files are compiled into executables and don't need dependencies
%info : %_info config.h
	$(PRE)$(CC) $(CCAN_CFLAGS) -I. -o $@ -x c $<

# config.h is built by configurator
CONFIGURATOR := tools/configurator/configurator
CONFIG_DEPS := $(CONFIGURATOR).d
$(CONFIGURATOR) : $(CONFIGURATOR).c
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEPENDENCY_FLAGS) $< -o $@
config.h: $(CONFIGURATOR) Makefile
	$(PRE)$(CONFIGURATOR) $(CC) $(CCAN_CFLAGS) $(DEPENDENCY_FLAGS) >$@.tmp && mv $@.tmp $@

# Tools are under the tools/ directory
TOOLS := ccan_depends doc_extract namespacize modfiles
TOOLS := $(TOOLS:%=tools/%)
TOOLS_SRCS := $(filter-out $(TOOLS:%=%.c), $(wildcard tools/*.c))
TOOLS_OBJS := $(TOOLS_SRCS:%.c=%.o)
TOOLS_DEPS := $(TOOLS_OBJS:%=%.d) $(TOOLS:%=%.d)
TOOLS_CCAN_MODULES := err foreach hash htable list noerr opt rbuf \
    read_write_all str take tal tal/grab_file tal/link tal/path \
    tal/str time
TOOLS_CCAN_SRCS := $(wildcard $(TOOLS_CCAN_MODULES:%=ccan/%/*.c))
TOOLS_CCAN_OBJS := $(TOOLS_CCAN_SRCS:%.c=%.o)
tools/% : tools/%.c $(TOOLS_OBJS) $(TOOLS_CCAN_OBJS)
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEPENDENCY_FLAGS) $^ -o $@ -lm

# ccanlint requires its own build rules
LINT := tools/ccanlint/ccanlint
LINT_SRCS := $(filter-out $(LINT).c, $(wildcard tools/ccanlint/*.c) $(wildcard tools/ccanlint/tests/*.c))
LINT_OBJS := $(LINT_SRCS:%.c=%.o)
LINT_DEPS := $(LINT_OBJS:%=%.d) $(LINT).d
LINT_CCAN_MODULES := asort autodata dgraph foreach hash htable ilog \
    lbalance list noerr opt ptr_valid rbuf read_write_all \
    str strmap take tal tal/grab_file tal/link tal/path \
    tal/str time
LINT_CCAN_SRCS := $(wildcard $(LINT_CCAN_MODULES:%=ccan/%/*.c))
LINT_CCAN_OBJS := $(LINT_CCAN_SRCS:%.c=%.o)
$(LINT) : $(LINT).c $(LINT_OBJS) $(TOOLS_OBJS) $(LINT_CCAN_OBJS)
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEPENDENCY_FLAGS) $^ -lm -o $@

# How to run ccanlint
LINT_CMD := $(LINT) --deps-fail-ignore

# Tests
# We generate dependencies for tests into a .deps file
%/.deps: %/info tools/gen_deps.sh tools/ccan_depends
	$(PRE)tools/gen_deps.sh $* $@
TEST_DEPS := $(MODULES:%=%/.deps)

# We produce .ok files when the tests succeed
%/.ok: $(LINT)
	$(PRE)$(LINT_CMD) -s $* && touch $@
TEST_RESULTS := $(MODULES:%=%/.ok)

%/.fast.ok: $(LINT)
	$(PRE)$(LINT_CMD) -x tests_pass_valgrind -x tests_compile_coverage -s $* && touch $@
FAST_TEST_RESULTS := $(MODULES:%=%/.fast.ok)

# 'make check/fastcheck' runs the summary/fast summary tests
check: $(TEST_RESULTS)
fastcheck: $(FAST_TEST_RESULTS)

# Bring in our generated dependencies
ifeq ($(CLEANING),false)
-include $(DEPS) $(TOOLS_DEPS) $(LINT_DEPS) $(TEST_DEPS)
endif

# Targets
.PHONY: clean TAGS

# Default target is the static library, info files and tools
all:: $(LIB) $(ALL_INFOS) $(CONFIGURATOR) $(LINT) $(TOOLS)

# Cleaning up
clean:
	$(PRE)rm -f $(DEPS) $(CONFIG_DEPS) $(LINT_DEPS) $(TOOLS_DEPS) $(TEST_DEPS)
	$(PRE)rm -f $(OBJS) $(TOOLS_OBJS) $(LINT_OBJS)
	$(PRE)rm -f $(LIB)
	$(PRE)rm -f $(CONFIGURATOR) $(LINT) $(TOOLS)
	$(PRE)rm -f $(TEST_RESULTS) $(FAST_TEST_RESULTS)
	$(PRE)rm -f TAGS config.h

# 'make TAGS' builds etags
TAGS:
	$(PRE)find * -name '*.[ch]' | xargs etags
