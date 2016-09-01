#! /bin/sh

# Compute the test dependencies for a ccan module. Usage:
# tools/gen_deps.sh ccan/path/to/module ccan/path/to/module/.deps

module_path=$1
deps_file=$2

# This test depends on the modules it uses passing their tests, which
# means we automatically depend on their object files being up to date,
# Since their .ok files depend on their object files.
deps=$(echo `$module_path/info testdepends` `$module_path/info depends`)
test_deps=`echo $deps | tr ' ' '\n' | sort | uniq | \
    sed -e 's/$/\/.ok/g' -e '/^\/.ok$/d' | tr '\n' ' '`
fast_test_deps=`echo $test_deps | sed 's/\.ok/.fast.ok/g'`

# We also depend on the source files of the modules tests
test_srcs=`ls $module_path/test/*.[ch] 2>/dev/null | tr '\n' ' '`

# And finally on the object files of our module. Actually, since we include
# module sources directly in tests this isn't strictly true; but it means
# that other tests depending on our test passing pick up the dependency
# without having to specify it recursively here. It also makes sure the
# module compiles properly rather than just when included in our test.
module_objs=`ls $module_path/*.c 2>/dev/null | sed 's/.c$/.o/g' | tr '\n' ' '`

# Declare our objects as a variable for possible use by others
module=`echo $module_path | sed 's/^ccan\///g'`
obj_var_decl="${module}_objs := $module_objs"

# Declare a module test target for short tests
test_target="${module}.test: $module_path/.ok"
fast_target="${module}.fasttest: $module_path/.fast.ok"

module_deps="$module_path/.ok: $module_objs $test_srcs $test_deps"
module_fast_deps="$module_path/.fast.ok: $module_objs $test_srcs $fast_test_deps"
echo "$module_deps\\n$module_fast_deps\\n$obj_var_decl\\n$test_target\\n$fast_target" > $deps_file
