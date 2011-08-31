#include <ccan/tdb2/private.h>
#include <unistd.h>
#include "tdb1-lock-tracking.h"
static ssize_t pwrite_check(int fd, const void *buf, size_t count, off_t offset);
static ssize_t write_check(int fd, const void *buf, size_t count);
static int ftruncate_check(int fd, off_t length);

#define pwrite pwrite_check
#define write write_check
#define fcntl fcntl_with_lockcheck1
#define ftruncate ftruncate_check

#include "tdb2-source.h"
#include <ccan/tap/tap.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdarg.h>
#include <err.h>
#include <setjmp.h>
#include "tdb1-external-agent.h"
#include "logging.h"

#undef write
#undef pwrite
#undef fcntl
#undef ftruncate

static bool in_transaction;
static int target, current;
static jmp_buf jmpbuf;
#define TEST_DBNAME "run-die-during-transaction.tdb"
#define KEY_STRING "helloworld"

static void maybe_die(int fd)
{
	if (in_transaction && current++ == target) {
		longjmp(jmpbuf, 1);
	}
}

static ssize_t pwrite_check(int fd,
			    const void *buf, size_t count, off_t offset)
{
	ssize_t ret;

	maybe_die(fd);

	ret = pwrite(fd, buf, count, offset);
	if (ret != count)
		return ret;

	maybe_die(fd);
	return ret;
}

static ssize_t write_check(int fd, const void *buf, size_t count)
{
	ssize_t ret;

	maybe_die(fd);

	ret = write(fd, buf, count);
	if (ret != count)
		return ret;

	maybe_die(fd);
	return ret;
}

static int ftruncate_check(int fd, off_t length)
{
	int ret;

	maybe_die(fd);

	ret = ftruncate(fd, length);

	maybe_die(fd);
	return ret;
}

static bool test_death(enum operation op, struct agent *agent)
{
	struct tdb_context *tdb = NULL;
	TDB_DATA key;
	enum agent_return ret;
	int needed_recovery = 0;
	union tdb_attribute hsize;

	hsize.base.attr = TDB_ATTRIBUTE_TDB1_HASHSIZE;
	hsize.base.next = &tap_log_attr;
	hsize.tdb1_hashsize.hsize = 1024;

	current = target = 0;
reset:
	unlink(TEST_DBNAME);
	tdb = tdb1_open(TEST_DBNAME, TDB_NOMMAP,
			O_CREAT|O_TRUNC|O_RDWR, 0600, &hsize);

	if (setjmp(jmpbuf) != 0) {
		/* We're partway through.  Simulate our death. */
		close(tdb->file->fd);
		forget_locking1();
		in_transaction = false;

		ret = external_agent_operation1(agent, NEEDS_RECOVERY, "");
		if (ret == SUCCESS)
			needed_recovery++;
		else if (ret != FAILED) {
			diag("Step %u agent NEEDS_RECOVERY = %s", current,
			     agent_return_name1(ret));
			return false;
		}

		ret = external_agent_operation1(agent, op, KEY_STRING);
		if (ret != SUCCESS) {
			diag("Step %u op %s failed = %s", current,
			     operation_name1(op),
			     agent_return_name1(ret));
			return false;
		}

		ret = external_agent_operation1(agent, NEEDS_RECOVERY, "");
		if (ret != FAILED) {
			diag("Still needs recovery after step %u = %s",
			     current, agent_return_name1(ret));
			return false;
		}

		ret = external_agent_operation1(agent, CHECK, "");
		if (ret != SUCCESS) {
			diag("Step %u check failed = %s", current,
			     agent_return_name1(ret));
			return false;
		}

		ret = external_agent_operation1(agent, CLOSE, "");
		if (ret != SUCCESS) {
			diag("Step %u close failed = %s", current,
			     agent_return_name1(ret));
			return false;
		}

		/* Suppress logging as this tries to use closed fd. */
		suppress_logging = true;
		suppress_lockcheck1 = true;
		tdb1_close(tdb);
		suppress_logging = false;
		suppress_lockcheck1 = false;
		target++;
		current = 0;
		goto reset;
	}

	/* Put key for agent to fetch. */
	key.dsize = strlen(KEY_STRING);
	key.dptr = (void *)KEY_STRING;
	if (tdb1_store(tdb, key, key, TDB_INSERT) != 0)
		return false;

	/* This is the key we insert in transaction. */
	key.dsize--;

	ret = external_agent_operation1(agent, OPEN, TEST_DBNAME);
	if (ret != SUCCESS)
		errx(1, "Agent failed to open: %s", agent_return_name1(ret));

	ret = external_agent_operation1(agent, FETCH, KEY_STRING);
	if (ret != SUCCESS)
		errx(1, "Agent failed find key: %s", agent_return_name1(ret));

	in_transaction = true;
	if (tdb1_transaction_start(tdb) != 0)
		return false;

	if (tdb1_store(tdb, key, key, TDB_INSERT) != 0)
		return false;

	if (tdb1_transaction_commit(tdb) != 0)
		return false;

	in_transaction = false;

	/* We made it! */
	diag("Completed %u runs", current);
	tdb1_close(tdb);
	ret = external_agent_operation1(agent, CLOSE, "");
	if (ret != SUCCESS) {
		diag("Step %u close failed = %s", current,
		     agent_return_name1(ret));
		return false;
	}

	ok1(needed_recovery);
	ok1(locking_errors1 == 0);
	ok1(forget_locking1() == 0);
	locking_errors1 = 0;
	return true;
}

int main(int argc, char *argv[])
{
	enum operation ops[] = { FETCH, STORE, TRANSACTION_START };
	struct agent *agent;
	int i;

	plan_tests(12);
	unlock_callback1 = maybe_die;

	agent = prepare_external_agent1();
	if (!agent)
		err(1, "preparing agent");

	for (i = 0; i < sizeof(ops)/sizeof(ops[0]); i++) {
		diag("Testing %s after death", operation_name1(ops[i]));
		ok1(test_death(ops[i], agent));
	}

	return exit_status();
}