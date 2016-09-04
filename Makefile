# Makefile for CCAN

# Adding 'quiet=1' to make arguments builds silently
QUIETEN.1 := @
PRE := $(QUIETEN.$(quiet))

# Adding 'opt=1' to make arguments builds optimised
OPT.1 := -O2
OPT_CFAGS := $(OPT.$(opt))

default: all

# Our flags for building
WARN_CFLAGS := -Wall -Wstrict-prototypes -Wold-style-definition -Wundef \
 -Wmissing-prototypes -Wmissing-declarations -Wpointer-arith -Wwrite-strings
DEP_CFLAGS = -MMD -MP -MF$(@:%=%.d) -MT$@
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
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEP_CFLAGS) -c $< -o $@

# _info files are compiled into executables and don't need dependencies
%info : %_info config.h
	$(PRE)$(CC) $(CCAN_CFLAGS) -I. -o $@ -x c $<

# config.h is built by configurator
CONFIGURATOR := tools/configurator/configurator
CONFIGURATOR_DEPS := $(CONFIGURATOR).d
$(CONFIGURATOR) : $(CONFIGURATOR).c
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEP_CFLAGS) $< -o $@
config.h: $(CONFIGURATOR) Makefile
	$(PRE)$(CONFIGURATOR) $(CC) $(CCAN_CFLAGS) $(DEP_CFLAGS) >$@.tmp && mv $@.tmp $@

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
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEP_CFLAGS) $< $(TOOLS_OBJS) $(TOOLS_CCAN_OBJS) -lm -o $@

# ccanlint requires its own build rules
LINT := tools/ccanlint/ccanlint
LINT_SRCS := $(filter-out $(LINT).c, $(wildcard tools/ccanlint/*.c) $(wildcard tools/ccanlint/tests/*.c))
LINT_OBJS := $(LINT_SRCS:%.c=%.o)
LINT_DEPS := $(LINT_OBJS:%=%.d) $(LINT).d
LINT_CCAN_MODULES := asort autodata dgraph ilog lbalance ptr_valid strmap
LINT_CCAN_SRCS := $(wildcard $(LINT_CCAN_MODULES:%=ccan/%/*.c))
LINT_CCAN_OBJS := $(LINT_CCAN_SRCS:%.c=%.o) $(TOOLS_OBJS) $(TOOLS_CCAN_OBJS)
$(LINT) : $(LINT).c $(LINT_OBJS) $(LINT_CCAN_OBJS)
	$(PRE)$(CC) $(CCAN_CFLAGS) $(DEP_CFLAGS) $(LINT).c $(LINT_OBJS) $(LINT_CCAN_OBJS) -lm -o $@

# Tests
LINT_OPTS.ok := -s
LINT_OPTS.fast.ok := -s -x tests_pass_valgrind -x tests_compile_coverage
LINT_CMD = $(LINT) $(LINT_OPTS$(notdir $@)) --deps-fail-ignore

# We generate dependencies for tests into a .deps file
%/.deps: %/info tools/gen_deps.sh tools/ccan_depends
	$(PRE)tools/gen_deps.sh $* $@
TEST_DEPS := $(MODULES:%=%/.deps)

# We produce .ok files when the tests succeed
%.ok: $(LINT)
	$(PRE)$(LINT_CMD) $(dir $*) && touch $@

check: $(MODULES:%=%/.ok)
fastcheck: $(MODULES:%=%/.fast.ok)

ifneq ($(filter clean, $(MAKECMDGOALS)),)
# Bring in our generated dependencies since we are not cleaning
-include $(DEPS) $(CONFIGURATOR_DEPS) $(LINT_DEPS) $(TOOLS_DEPS) $(TEST_DEPS)
endif

# Default target is the object files, info files and tools
all:: $(OBJS) $(ALL_INFOS) $(CONFIGURATOR) $(LINT) $(TOOLS)

.PHONY: clean TAGS
clean:
	$(PRE)find . -name "*.o" -o -name "*.d" -o -name "*.ok" -o -name ".deps" -delete
	$(PRE)rm -f $(CONFIGURATOR) $(LINT) $(TOOLS) TAGS config.h config.h.d

# 'make TAGS' builds etags
TAGS:
	$(PRE)find * -name '*.[ch]' | xargs etags
